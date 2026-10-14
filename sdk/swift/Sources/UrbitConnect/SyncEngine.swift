import Foundation

struct ServerFailure: Error, Sendable {
    let status: Int
    let code: String
    let message: String
    let detail: JSONObject
    let retryAfter: TimeInterval?
    init(_ response: HTTPResponse) throws {
        // An ingress or Gall restart can return an empty/HTML error response.
        // Only successful protocol bodies establish a protocol-data failure.
        let wire = (try? response.json) ?? [:]
        detail = wire["error"]?.objectValue ?? wire
        status = response.status; code = detail["code"]?.stringValue ?? wire["error"]?.stringValue ?? (response.status >= 500 ? "service_unavailable" : "request_failed")
        let explanation = detail["message"]?.stringValue ?? wire["error_description"]?.stringValue
        message = explanation.map { String($0.prefix(512)) } ?? "The ship is temporarily unavailable. Pending edits remain on this device."
        retryAfter = response.retryAfter.flatMap { $0.isFinite && $0 >= 0 ? min(60, $0) : nil }
    }
}

enum RetryDelay {
    static func seconds(backoff: UInt64, retryAfter: TimeInterval?) -> TimeInterval {
        let base = retryAfter.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? Double(backoff)
        return min(60, max(1, base) * Double.random(in: 1...1.2))
    }
}

extension Revision: Comparable {
    public static func < (lhs: Revision, rhs: Revision) -> Bool {
        lhs.rawValue.count != rhs.rawValue.count ? lhs.rawValue.count < rhs.rawValue.count : lhs.rawValue < rhs.rawValue
    }
}

enum SyncCodec {
    static func info(_ wire: JSONObject, origin: URL, expected: ConnectAccount? = nil) throws -> ConnectAccount {
        guard wire["protocolVersion"] == .number("1"), wire["configured"] == .bool(true) else { throw ConnectError.protocolMismatch }
        let account = try ConnectAccount(wire: wire)
        guard account.issuer.absoluteString == origin.appending(path: "connect").absoluteString,
              !account.instanceId.isEmpty, account.instanceId.utf8.count <= 128 else { throw ConnectError.invalidOrigin }
        if let expected {
            guard account.issuer == expected.issuer, account.instanceId == expected.instanceId else { throw ConnectError.accountChanged }
            guard account.syncEpoch == expected.syncEpoch else { throw ConnectError.restoreDetected }
        }
        return account
    }
    static func commit(_ wire: JSONObject, mutation: StoredMutation) throws -> Revision {
        let revision = try Revision(wire.string("revision")), results = try wire.array("results")
        let lowerBound = try mutation.expected ?? Revision("0")
        guard results.count == 1, let result = results[0].objectValue,
              try result.string("id") == mutation.documentID.uuidString.lowercased(),
              try result.string("collection") == mutation.collection,
              try Revision(result.string("revision")) == revision,
              result["deleted"]?.boolValue == (mutation.draft == nil), revision > lowerBound else { throw ConnectError.protocolMismatch }
        return revision
    }
    static func changes(_ wire: JSONObject) throws -> [RemoteChange] {
        var changes: [RemoteChange] = []
        var lastRevision: Revision?
        for item in try wire.array("batches") {
            guard let batch = item.objectValue else { throw ConnectError.protocolMismatch }
            let revision = try Revision(batch.string("revision"))
            guard lastRevision.map({ $0 < revision }) ?? true else { throw ConnectError.protocolMismatch }
            lastRevision = revision
            for item in try batch.array("changes") {
                guard let value = item.objectValue, let deleted = value["deleted"]?.boolValue else { throw ConnectError.protocolMismatch }
                if deleted {
                    let collection = try value.string("collection"), raw = try value.string("id")
                    guard ConnectIdentifiers.collection(collection), ConnectIdentifiers.document(raw), let id = UUID(uuidString: raw), try Revision(value.string("revision")) == revision else { throw ConnectError.protocolMismatch }
                    changes.append(.delete(collection: collection, id: id))
                } else {
                    let document = try ConnectDocument(wire: value.object("document"))
                    guard document.revision == revision else { throw ConnectError.protocolMismatch }
                    changes.append(.put(document))
                }
            }
        }
        return changes
    }
}

public enum ConflictResolution: Equatable, Sendable { case useRemote, retryWithCurrent, saveAsNewDocument }
