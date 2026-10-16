import Foundation
import Testing
@testable import UrbitConnect

struct DraftArchiveTests {
    @Test func accountReplacementAndRevocationKeepExportableDraftsWithoutCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-archives-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = ShipTransport(), next = ShipTransport(origin: "https://other.example", instance: "next")
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        let client = try ConnectClient(configuration: config, persistenceDirectory: root, tokens: MemoryTokenStore(), transport: { $0.host == "other.example" ? next : old }, automaticallySync: false)
        let account = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        let id = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Local-only draft")], expectedRevision: nil)
        _ = try await client.connect(to: URL(string: "https://other.example")!, presentation: TestPresenter())
        let archive = try #require(await client.retainedAccounts().first { $0.account == account })
        #expect(archive.pendingCount == 1)
        let data = try await client.exportDrafts(archiveID: archive.id)
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains("Local-only draft")); #expect(raw.contains(id.rawValue.uuidString.lowercased()))
        for forbidden in ["access_token", "refresh_token", "test-access", "test-refresh", "code_verifier", "urbauth"] { #expect(!raw.contains(forbidden)) }
        try await client.disconnect()
        #expect(try await client.retainedAccounts().count == 2)
        #expect(try await client.exportDrafts(archiveID: archive.id) == data)
        await #expect(throws: ConnectError.invalidIdentifier) { try await client.removeRetainedAccount(archiveID: archive.id, confirmation: "wrong") }
        try await client.removeRetainedAccount(archiveID: archive.id, confirmation: archive.id)
        #expect(try await client.retainedAccounts().count == 1)
    }
}
