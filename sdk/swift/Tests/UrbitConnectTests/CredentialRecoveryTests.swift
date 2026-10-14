import Foundation
import Testing
@testable import UrbitConnect

struct CredentialRecoveryTests {
    private func make(_ ship: ShipTransport, directory: URL, tokens: MemoryTokenStore, clock: TestClock = .init()) throws -> ConnectClient {
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        return try ConnectClient(configuration: config, persistenceDirectory: directory, tokens: tokens, transport: { _ in ship }, clock: { clock.now() }, automaticallySync: false)
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: "connect-credentials-" + UUID().uuidString) }
    @Test func failedCredentialWriteCannotAcceptPairingOrAnEdit() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore(), root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = try make(ship, directory: root, tokens: tokens)
        tokens.failWrites(true)
        await #expect(throws: ConnectError.self) { try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter()) }
        #expect(await client.account() == nil)
        await #expect(throws: ConnectError.notConnected) { try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Rejected input")], expectedRevision: nil) }
        tokens.failWrites(false)
        #expect(try await make(ship, directory: root, tokens: tokens).resume() == nil)
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        #expect(await client.connectionStatus() == .online)
    }
    @Test func selectedAccountWriteFailureDoesNotReportSuccessfulPairing() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore(), root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = try make(ship, directory: root, tokens: tokens)
        let selection = root.appending(path: "selected-" + Data("connect-test".utf8).sha256Hex + ".txt")
        // A real filesystem write failure, scoped to this new fixture directory.
        try FileManager.default.createDirectory(at: selection, withIntermediateDirectories: true)
        do { _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter()); Issue.record("Pairing accepted an unwritable selection") }
        catch { #expect(await client.account() == nil) }
        await #expect(throws: ConnectError.notConnected) { try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Rejected input")], expectedRevision: nil) }
        try FileManager.default.removeItem(at: selection)
        #expect(try await make(ship, directory: root, tokens: tokens).resume() == nil)
        let account = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        #expect(try await make(ship, directory: root, tokens: tokens).resume() == account)
    }
    @Test func failedCredentialDeletionIsReportedAndRetainsDraftsForRetry() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore(), root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = try make(ship, directory: root, tokens: tokens)
        let account = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Keep")], expectedRevision: nil)
        tokens.failDeletes(true)
        await #expect(throws: ConnectError.self) { try await client.disconnect() }
        #expect(await client.account() == account)
        #expect(try await client.recoveryDrafts().count == 1)
        #expect(try await make(ship, directory: root, tokens: tokens).resume() == account)
        tokens.failDeletes(false); try await client.disconnect()
        let reopened = try make(ship, directory: root, tokens: tokens)
        #expect(try await reopened.resume() == nil)
        #expect(try await reopened.recoveryDrafts().first?.status == .needsAttention)
    }
    @Test func refreshCannotReachShipUntilItsAmbiguityMarkerIsDurable() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore(), root = directory(), clock = TestClock()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = try make(ship, directory: root, tokens: tokens, clock: clock)
        let account = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        try await client.syncOnce(); clock.advance(700); tokens.failWrites(true)
        await #expect(throws: ConnectError.self) { try await client.syncOnce() }
        #expect(await ship.refreshes() == 0)
        tokens.failWrites(false)
        let reopened = try make(ship, directory: root, tokens: tokens, clock: clock)
        #expect(try await reopened.resume() == account)
        try await reopened.syncOnce(); #expect(await ship.refreshes() == 1)
    }
}
