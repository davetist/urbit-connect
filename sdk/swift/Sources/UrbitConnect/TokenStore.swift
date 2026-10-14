import Foundation
import Security

protocol TokenStore: Sendable {
    func read(key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func delete(key: String) throws
}
struct KeychainTokenStore: TokenStore {
    let service: String
    init(service: String = "org.urbit.connect.credentials.v1") { self.service = service }
    private func query(key: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
    func read(key: String) throws -> Data? {
        var query = query(key: key); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ConnectError.storage("Keychain read failed (\(status))") }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let query = query(key: key)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw ConnectError.storage("Keychain update failed (\(updated))") }
        var added = query; attributes.forEach { added[$0.key] = $0.value }
        let status = SecItemAdd(added as CFDictionary, nil)
        guard status == errSecSuccess else { throw ConnectError.storage("Keychain save failed (\(status))") }
    }
    func delete(key: String) throws {
        let status = SecItemDelete(query(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ConnectError.storage("Keychain removal failed (\(status))") }
    }
}

struct Credentials: Sendable {
    var account: ConnectAccount
    var grant: ConnectGrant
    var access: String
    var refresh: String
    var accessExpires: Date
    var refreshInFlight: Bool
    func encoded() throws -> Data {
        try JSONValue.object(["account": .object(account.wire), "grant": .object(grant.wire), "access": .string(access), "refresh": .string(refresh), "accessExpires": .string(String(accessExpires.timeIntervalSince1970)), "refreshInFlight": .bool(refreshInFlight)]).encoded()
    }
    static func decode(_ data: Data) throws -> Credentials {
        guard let wire = try JSONValue.parse(data).objectValue, let expiry = Double(try wire.string("accessExpires")), let inFlight = wire["refreshInFlight"]?.boolValue else { throw ConnectError.storage("Invalid credential record") }
        return try .init(account: .init(wire: wire.object("account")), grant: .init(wire: wire.object("grant")), access: wire.string("access"), refresh: wire.string("refresh"), accessExpires: Date(timeIntervalSince1970: expiry), refreshInFlight: inFlight)
    }
}
