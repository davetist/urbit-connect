import Foundation

extension JSONObject {
    func string(_ key: String) throws -> String {
        guard let value = self[key]?.stringValue else { throw ConnectError.invalidJSON("Missing string field: \(key)") }
        return value
    }
    func object(_ key: String) throws -> JSONObject {
        guard let value = self[key]?.objectValue else { throw ConnectError.invalidJSON("Missing object field: \(key)") }
        return value
    }
    func array(_ key: String) throws -> [JSONValue] {
        guard let value = self[key]?.arrayValue else { throw ConnectError.invalidJSON("Missing array field: \(key)") }
        return value
    }
}
extension ConnectAccount {
    init(wire: JSONObject) throws {
        guard let url = URL(string: try wire.string("issuer")) else { throw ConnectError.invalidOrigin }
        issuer = url; instanceId = try wire.string("instanceId"); ship = try wire.string("ship")
        syncEpoch = try Revision(wire.string("syncEpoch"))
        isDevelopment = wire["development"]?.boolValue ?? false
    }
    var wire: JSONObject { ["issuer": .string(issuer.absoluteString), "instanceId": .string(instanceId), "ship": .string(ship), "syncEpoch": .string(syncEpoch.rawValue), "development": .bool(isDevelopment)] }
}
extension ConnectGrant {
    init(wire: JSONObject) throws {
        id = try wire.string("id"); clientId = try wire.string("clientId"); namespace = try wire.string("namespace")
        namespaceEpoch = try Revision(wire.string("namespaceEpoch")); sessionId = try wire.string("sessionId")
        scopes = try wire.array("scopes").map { value in
            guard let scope = value.stringValue else { throw ConnectError.invalidJSON("Invalid scope") }; return scope
        }
    }
    var wire: JSONObject { ["id": .string(id), "clientId": .string(clientId), "namespace": .string(namespace), "namespaceEpoch": .string(namespaceEpoch.rawValue), "sessionId": .string(sessionId), "scopes": .array(scopes.map(JSONValue.string))] }
}
extension ConnectDocument {
    init(wire: JSONObject) throws {
        let raw = try wire.string("id"), collection = try wire.string("collection")
        guard ConnectIdentifiers.document(raw), let id = UUID(uuidString: raw), ConnectIdentifiers.collection(collection) else { throw ConnectError.invalidIdentifier }
        self.id = id; self.collection = collection; data = try wire.object("data")
        _ = try JSONValue.object(data).encoded()
        revision = try Revision(wire.string("revision")); updatedAt = try wire.string("updatedAt")
    }
    var wire: JSONObject { ["id": .string(id.uuidString.lowercased()), "collection": .string(collection), "data": .object(data), "revision": .string(revision.rawValue), "updatedAt": .string(updatedAt)] }
}

struct StoredMutation: Equatable, Sendable {
    let id: PendingMutationID
    let collection: String
    let documentID: UUID
    let draft: JSONObject?
    var expected: Revision?
    let createdAt: Date
    var body: Data?
    var status: MutationStatus
    var dependsOn: PendingMutationID?
    var message: String?
    var current: ConnectDocument?
    var acknowledged: Revision?
    func requestBody(expectedOverride: Revision? = nil) throws -> Data {
        var op: JSONObject = ["type": .string(draft == nil ? "delete" : "put"), "collection": .string(collection), "id": .string(documentID.uuidString.lowercased()), "expectedRevision": (expectedOverride ?? expected).map { .string($0.rawValue) } ?? .null]
        if let draft { op["data"] = .object(draft) }
        return try JSONValue.object(["requestId": .string(id.rawValue.uuidString.lowercased()), "operations": .array([.object(op)])]).encoded(maxDepth: 24)
    }
    var publicValue: PendingMutation { .init(id: id, collection: collection, documentID: documentID, draft: draft, status: status, message: message, current: current) }
}

extension StoredMutation {
    func encoded() throws -> Data {
        let wire: JSONObject = [
            "id": .string(id.rawValue.uuidString.lowercased()), "collection": .string(collection), "documentID": .string(documentID.uuidString.lowercased()),
            "draft": draft.map(JSONValue.object) ?? .null, "expected": expected.map { .string($0.rawValue) } ?? .null,
            "created": .string(String(createdAt.timeIntervalSince1970)), "body": body.map { .string($0.base64EncodedString()) } ?? .null,
            "status": .string(status.rawValue), "dependsOn": dependsOn.map { .string($0.rawValue.uuidString.lowercased()) } ?? .null,
            "message": message.map(JSONValue.string) ?? .null, "current": current.map { .object($0.wire) } ?? .null,
            "acknowledged": acknowledged.map { .string($0.rawValue) } ?? .null
        ]
        return try JSONValue.object(wire).encoded(maxDepth: 24)
    }
    static func decode(_ data: Data) throws -> StoredMutation {
        guard let wire = try JSONValue.parse(data, maxDepth: 24).objectValue,
              let id = UUID(uuidString: try wire.string("id")), let documentID = UUID(uuidString: try wire.string("documentID")),
              let created = Double(try wire.string("created")), let status = MutationStatus(rawValue: try wire.string("status")) else {
            throw ConnectError.storage("Corrupt pending mutation")
        }
        let dependsOn = try wire["dependsOn"]?.stringValue.map { raw -> PendingMutationID in
            guard let uuid = UUID(uuidString: raw) else { throw ConnectError.storage("Corrupt mutation dependency") }; return .init(rawValue: uuid)
        }
        let body = try wire["body"]?.stringValue.map { raw -> Data in
            guard let bytes = Data(base64Encoded: raw) else { throw ConnectError.storage("Corrupt request bytes") }; return bytes
        }
        return try .init(id: .init(rawValue: id), collection: wire.string("collection"), documentID: documentID,
                         draft: wire["draft"]?.objectValue, expected: wire["expected"]?.stringValue.map(Revision.init),
                         createdAt: Date(timeIntervalSince1970: created), body: body, status: status, dependsOn: dependsOn,
                         message: wire["message"]?.stringValue, current: wire["current"]?.objectValue.map(ConnectDocument.init(wire:)), acknowledged: wire["acknowledged"]?.stringValue.map(Revision.init))
    }
}
