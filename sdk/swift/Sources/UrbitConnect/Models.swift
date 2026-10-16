import Foundation

public enum ConnectError: Error, Equatable, Sendable {
    case invalidJSON(String), invalidIdentifier, invalidRevision, protocolMismatch
    case invalidOrigin, unauthorized, notConnected, authorizationDenied, authorizationCancelled, accountChanged, restoreDetected, storage(String), transport(String)
    case server(status: Int, code: String, message: String)
    @available(*, deprecated, message: "Connect no longer enforces local product quotas; handle storage errors instead.")
    case localCapacity(resource: LocalCapacityResource, limit: Int)
    case missingDesk, notConfigured, unsupportedProtocol
}

/// A pasted manager address is a suggestion; the app must confirm its base origin.
public struct ConnectEndpoint: Equatable, Sendable {
    public let origin: URL
    public let requiresConfirmation: Bool
    public init(_ address: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw ConnectError.invalidOrigin }
        requiresConfirmation = ["/apps/connect", "/apps/connect/"].contains(parts.percentEncodedPath)
        if requiresConfirmation { parts.path = "" }
        guard let base = parts.url else { throw ConnectError.invalidOrigin }
        origin = try HTTPTransport.validateOrigin(base)
    }
}

/// Retained for source compatibility; Connect no longer emits local quota errors.
@available(*, deprecated, message: "Connect no longer enforces local product quotas.")
public enum LocalCapacityResource: Equatable, Sendable { case pendingMutations, pendingRequestBytes, retainedAccounts }

public struct Revision: Codable, Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) throws {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              value == "0" || value.first != "0", value.count <= 128 else { throw ConnectError.invalidRevision }
        rawValue = value
    }
    public init(from decoder: any Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
}

/// JSON numbers retain their source spelling. Encoding validates values even when constructed directly.
/// The default byte bound is Data's Int representation limit, not a product quota.
public enum JSONValue: Equatable, Sendable {
    case null, bool(Bool), string(String), number(String), array([JSONValue]), object(JSONObject)
    public static func parse(_ data: Data, maxBytes: Int = .max, maxDepth: Int = 16) throws -> JSONValue {
        guard (1...24).contains(maxDepth), data.count <= maxBytes, String(data: data, encoding: .utf8) != nil else {
            throw ConnectError.invalidJSON("Input exceeds its byte limit or is not UTF-8")
        }
        var parser = JSONParser(bytes: Array(data), maxDepth: maxDepth)
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw ConnectError.invalidJSON("Trailing input") }
        return value
    }
    public func encoded(maxBytes: Int = .max, maxDepth: Int = 16) throws -> Data {
        guard (1...24).contains(maxDepth) else { throw ConnectError.invalidJSON("Invalid depth bound") }
        let data = try rawEncoded(depth: 0, maxDepth: maxDepth)
        _ = try Self.parse(data, maxBytes: maxBytes, maxDepth: maxDepth)
        return data
    }
    private func rawEncoded(depth: Int, maxDepth: Int) throws -> Data {
        guard depth <= maxDepth else { throw ConnectError.invalidJSON("JSON depth exceeds \(maxDepth)") }
        switch self {
        case .null: return Data("null".utf8)
        case .bool(let value): return Data((value ? "true" : "false").utf8)
        case .number(let value):
            guard try Self.parse(Data(value.utf8)) == self else { throw ConnectError.invalidJSON("Invalid number") }
            return Data(value.utf8)
        case .string(let value): return try Self.encodeString(value)
        case .array(let values):
            return try Self.join(values.map { try $0.rawEncoded(depth: depth + 1, maxDepth: maxDepth) }, open: "[", close: "]")
        case .object(let fields):
            let pairs = try fields.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { key -> Data in
                var result = try Self.encodeString(key)
                result.append(58); result.append(try fields[key]!.rawEncoded(depth: depth + 1, maxDepth: maxDepth)); return result
            }
            return Self.join(pairs, open: "{", close: "}")
        }
    }
    private static func encodeString(_ value: String) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
        return try encoder.encode(value)
    }
    private static func join(_ parts: [Data], open: String, close: String) -> Data {
        var data = Data(open.utf8)
        for (index, part) in parts.enumerated() { if index > 0 { data.append(44) }; data.append(part) }
        data.append(contentsOf: close.utf8); return data
    }
    public var objectValue: JSONObject? { if case .object(let value) = self { value } else { nil } }
    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
}
/// Keys compare by their decoded UTF-8 bytes, as JSON requires. Swift String
/// equality alone would conflate distinct canonically equivalent Unicode keys.
public struct JSONObject: Equatable, Sendable, ExpressibleByDictionaryLiteral {
    private var storage: [Data: Entry] = [:]
    private struct Entry: Equatable, Sendable { let key: String; var value: JSONValue }
    public init() {}
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        for (key, value) in elements { self[key] = value }
    }
    public subscript(key: String) -> JSONValue? {
        get { storage[Data(key.utf8)]?.value }
        set { storage[Data(key.utf8)] = newValue.map { Entry(key: key, value: $0) } }
    }
    public var keys: [String] { storage.values.map(\.key) }
    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
}

public enum ConnectIdentifiers {
    public static func collection(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard let first = bytes.first, (97...122).contains(first), bytes.count <= 48 else { return false }
        return bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
    public static func document(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 36 else { return false }
        return bytes.enumerated().allSatisfy { index, byte in
            [8, 13, 18, 23].contains(index) ? byte == 45 : (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

public struct ConnectAccount: Equatable, Sendable {
    public let issuer: URL
    public let instanceId: String
    public let ship: String
    public let syncEpoch: Revision
    public let isDevelopment: Bool
}
public struct ConnectGrant: Equatable, Sendable {
    public let id: String
    public let clientId: String
    public let namespace: String
    public let namespaceEpoch: Revision
    public let scopes: [String]
    public let sessionId: String
}
public struct ConnectDocument: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let collection: String
    public let data: JSONObject
    public let revision: Revision
    public let updatedAt: String
}
public struct PendingMutationID: Codable, Hashable, Sendable { public let rawValue: UUID }
public enum MutationStatus: String, Codable, Sendable { case pending, sending, conflict, needsAttention }
public struct PendingMutation: Equatable, Sendable, Identifiable {
    public let id: PendingMutationID
    public let collection: String
    public let documentID: UUID
    public let draft: JSONObject?
    public let status: MutationStatus
    public let message: String?
    public let current: ConnectDocument?
}
public struct RetainedAccount: Equatable, Sendable, Identifiable {
    public let id: String
    public let account: ConnectAccount?
    public let pendingCount: Int
    public let isSelected: Bool
}
public enum ConnectionStatus: Equatable, Sendable { case disconnected, connecting, online, offline, revoked, needsAuthorization }
public struct CollectionState: Equatable, Sendable {
    public let documents: [ConnectDocument]
    public let pending: [PendingMutation]
    public let hydrated: Bool
    public let connection: ConnectionStatus
    public let message: String?
}
