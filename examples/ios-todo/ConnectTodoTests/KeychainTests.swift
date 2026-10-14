import Foundation
import Testing
@testable import UrbitConnect

struct TokenStoreTests {
    @Test func testTokenStoreSeparatesAccounts() throws {
        let store = KeychainTokenStore(service: "org.urbit.connect.test." + UUID().uuidString)
        defer { try? store.delete(key: "account-a/client-one"); try? store.delete(key: "account-b/client-one") }
        try store.write(Data("test-only-a".utf8), key: "account-a/client-one")
        try store.write(Data("test-only-b".utf8), key: "account-b/client-one")
        #expect(try store.read(key: "account-a/client-one") == Data("test-only-a".utf8))
        #expect(try store.read(key: "account-b/client-one") == Data("test-only-b".utf8))
        try store.delete(key: "account-a/client-one")
        #expect(try store.read(key: "account-a/client-one") == nil)
        #expect(try store.read(key: "account-b/client-one") == Data("test-only-b".utf8))
    }
}
