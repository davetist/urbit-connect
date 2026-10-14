import Foundation
import Testing
@testable import UrbitConnect

@MainActor final class WaitingPresenter: AuthorizationPresenter {
    var continuation: CheckedContinuation<Void, Never>?
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        await withCheckedContinuation { continuation = $0 }
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        return URL(string: "org.example.connect.test:/oauth/callback?code=test-code&state=" + state)!
    }
    func release() { continuation?.resume(); continuation = nil }
    var waiting: Bool { continuation != nil }
}

struct LifecycleTests {
    @Test func disconnectNeverRefreshesAnAmbiguousCapturedCredential() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore(), endpoint = ExpiredRevokeTransport(ship: ship, tokens: tokens)
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-logout-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        let client = try ConnectClient(configuration: config, persistenceDirectory: root, tokens: tokens, transport: { _ in endpoint }, automaticallySync: false)
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        let selected = try String(contentsOf: root.appending(path: "selected-" + Data("connect-test".utf8).sha256Hex + ".txt"), encoding: .utf8)
        let record = try tokens.read(key: selected)
        var saved = try Credentials.decode(try #require(record)); saved.refreshInFlight = true
        try tokens.write(saved.encoded(), key: selected); _ = try await client.resume(); await endpoint.setSelected(selected)
        await #expect(throws: ServerFailure.self) { try await client.disconnect() }
        #expect(await endpoint.refreshRequests == 0); #expect(try tokens.read(key: selected) == nil)
    }
    @Test func disconnectRefreshesExpiredCapturedAccessWithoutRestoringLocalCredentials() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore(), endpoint = ExpiredRevokeTransport(ship: ship, tokens: tokens)
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-logout-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        let client = try ConnectClient(configuration: config, persistenceDirectory: root, tokens: tokens, transport: { _ in endpoint }, automaticallySync: false)
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        let selected = try String(contentsOf: root.appending(path: "selected-" + Data("connect-test".utf8).sha256Hex + ".txt"), encoding: .utf8)
        await endpoint.setSelected(selected)
        _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Keep this logout draft")], expectedRevision: nil)
        try await client.disconnect()
        #expect(await endpoint.refreshRequests == 1); #expect(await endpoint.successfulRevokes == 1)
        #expect(await client.account() == nil); #expect(try tokens.read(key: selected) == nil)
        let reopened = try ConnectClient(configuration: config, persistenceDirectory: root, tokens: tokens, transport: { _ in endpoint }, automaticallySync: false)
        #expect(try await reopened.resume() == nil); #expect(try await reopened.recoveryDrafts().count == 1)
    }
    private func make(old: ShipTransport, next: ShipTransport, clock: TestClock = .init(), automatic: Bool = false, tokens: MemoryTokenStore = .init()) throws -> (ConnectClient, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "connect-lifecycle-" + UUID().uuidString)
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        let client = try ConnectClient(configuration: config, persistenceDirectory: directory, tokens: tokens, transport: { origin in
            origin.host == "other.example" ? next : old
        }, clock: { clock.now() }, automaticallySync: automatic)
        return (client, directory)
    }
    @Test func backgroundOrTerminationDuringDisconnectCannotResumeTheOldCredentials() async throws {
        let old = ShipTransport(), next = ShipTransport(), tokens = MemoryTokenStore()
        let (client, directory) = try make(old: old, next: next, tokens: tokens)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Retain this draft")], expectedRevision: nil)
        await old.pauseNextRevoke()
        let stopping = Task { try await client.disconnect() }
        for _ in 0..<200 { if await old.pausedRevoke != nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(await old.pausedRevoke != nil)
        await client.setForeground(false)
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        let reopened = try ConnectClient(configuration: config, persistenceDirectory: directory, tokens: tokens, transport: { _ in old }, automaticallySync: false)
        #expect(try await reopened.resume() == nil)
        #expect(try await reopened.recoveryDrafts().count == 1)
        await old.releaseRevoke(); _ = try? await stopping.value
        #expect(try await client.resume() == nil)
    }
    @Test func pairingAndDisconnectCannotAcceptEditsForThePreviousAccount() async throws {
        let old = ShipTransport(), next = ShipTransport(origin: "https://other.example", instance: "next")
        let (client, directory) = try make(old: old, next: next)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        let presenter = WaitingPresenter()
        let pairing = Task { try await client.connect(to: URL(string: "https://other.example")!, presentation: presenter) }
        for _ in 0..<200 { if await presenter.waiting { break }; try await Task.sleep(for: .milliseconds(5)) }
        await #expect(throws: ConnectError.notConnected) {
            try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Wrong account")], expectedRevision: nil)
        }
        await presenter.release(); _ = try await pairing.value
        await next.pauseNextRevoke()
        let stopping = Task { try await client.disconnect() }
        for _ in 0..<200 { if await next.pausedRevoke != nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        await #expect(throws: ConnectError.notConnected) {
            try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Disconnected")], expectedRevision: nil)
        }
        await next.releaseRevoke(); _ = try? await stopping.value
    }
    @Test func supersededDisconnectCannotClearTheNewAccount() async throws {
        let old = ShipTransport(), next = ShipTransport(origin: "https://other.example", instance: "new-instance")
        let (client, directory) = try make(old: old, next: next)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        await old.pauseNextRevoke()
        let stopping = Task { try await client.disconnect() }
        for _ in 0..<200 { if await old.pausedRevoke != nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(await old.pausedRevoke != nil)
        let account = try await client.connect(to: URL(string: "https://other.example")!, presentation: TestPresenter())
        let id = UUID(); try await next.remotePut(id: id, title: "New account content"); try await client.syncOnce()
        _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("New draft")], expectedRevision: nil)
        await old.releaseRevoke(); _ = try? await stopping.value
        #expect(await client.account() == account)
        #expect(await client.connectionStatus() == .online)
        #expect(try await client.get(collection: "lists", id: id)?.data["title"] == .string("New account content"))
        #expect(try await client.recoveryDrafts().first?.status == .pending)
        #expect(try await client.resume() == account)
    }
    @Test func foregroundDuringPairingCannotSyncOrRefreshThePreviousAccount() async throws {
        let old = ShipTransport(), next = ShipTransport(origin: "https://other.example", instance: "new-instance"), clock = TestClock()
        await old.occupyPoll(); await next.occupyPoll()
        let (client, directory) = try make(old: old, next: next, clock: clock, automatic: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        await client.setForeground(false)
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        try await client.syncOnce(); clock.advance(700); await old.pauseNextRefresh()
        let before = await old.infoCount
        let presenter = WaitingPresenter()
        let pairing = Task { try await client.connect(to: URL(string: "https://other.example")!, presentation: presenter) }
        for _ in 0..<200 { if await presenter.waiting { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(await presenter.waiting)
        await client.setForeground(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await old.infoCount == before)
        #expect(await old.refreshes() == 0)
        await presenter.release(); let account = try await pairing.value
        await old.releaseRefresh()
        try await Task.sleep(for: .milliseconds(100))
        await client.setForeground(false)
        #expect(await client.account() == account)
        let id = UUID(); try await next.remotePut(id: id, title: "New ship only")
        try await client.syncOnce()
        #expect(try await client.documents(in: "lists").map(\.id) == [id])
    }
}

actor ExpiredRevokeTransport: ConnectTransport {
    let ship: ShipTransport; let tokens: MemoryTokenStore
    var selected: String?; var refreshRequests = 0; var successfulRevokes = 0
    init(ship: ShipTransport, tokens: MemoryTokenStore) { self.ship = ship; self.tokens = tokens }
    func setSelected(_ key: String) { selected = key }
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse {
        if path == "/connect/oauth/revoke" {
            if let selected { #expect(try tokens.read(key: selected) == nil) }
            if token != "refreshed-for-revocation" {
                return .init(status: 401, body: try JSONValue.object(["error": .object(["code": .string("invalid_token"), "message": .string("Expired")])]).encoded(), retryAfter: nil)
            }
            successfulRevokes += 1
        }
        let response = try await ship.send(path: path, method: method, body: body, token: token, form: form)
        if path == "/connect/oauth/token", String(decoding: body ?? Data(), as: UTF8.self).contains("grant_type=refresh_token") {
            if let selected { #expect(try tokens.read(key: selected) == nil) }
            refreshRequests += 1
            var wire = try response.json; wire["access_token"] = .string("refreshed-for-revocation")
            return .init(status: response.status, body: try JSONValue.object(wire).encoded(), retryAfter: nil)
        }
        return response
    }
}
