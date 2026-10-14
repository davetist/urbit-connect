import Foundation
import Testing
@testable import UrbitConnect

actor InterruptedTransport: ConnectTransport {
    let ship: ShipTransport
    var interruptPoll = true
    init(ship: ShipTransport) { self.ship = ship }
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse {
        if interruptPoll && path.contains("wait=25") {
            interruptPoll = false
            return .init(status: 502, body: Data("<html>upstream restarted</html>".utf8), retryAfter: nil)
        }
        return try await ship.send(path: path, method: method, body: body, token: token, form: form)
    }
}

struct ReliabilityTests {
    @Test func availabilityReplyDuringRefreshRequiresAuthorizationWithoutReplayingItOrLosingDrafts() async throws {
        let ship = ShipTransport(), transport = UnavailableRefreshTransport(ship: ship), tokens = MemoryTokenStore(), clock = TestClock()
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-refresh-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        func make() throws -> ConnectClient { try ConnectClient(configuration: config, persistenceDirectory: root, tokens: tokens, transport: { _ in transport }, clock: { clock.now() }, automaticallySync: false) }
        let client = try make()
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Keep across ambiguous refresh")], expectedRevision: nil)
        let before = try await client.pendingForTesting(); clock.advance(700)
        do { try await client.syncOnce(); Issue.record("Ambiguous refresh was accepted") } catch let failure as ServerFailure { #expect(failure.status == 503) }
        #expect(await client.connectionStatus() == .needsAuthorization)
        #expect(await ship.refreshes() == 1)
        let reopened = try make(); _ = try await reopened.resume()
        #expect(await reopened.connectionStatus() == .needsAuthorization)
        await #expect(throws: ConnectError.notConnected) { try await reopened.syncOnce() }
        #expect(await ship.refreshes() == 1)
        let drafts = try await reopened.pendingForTesting()
        #expect(drafts.map(\.id) == before.map(\.id)); #expect(drafts.map(\.body) == before.map(\.body))
        #expect(drafts.allSatisfy { $0.status == .needsAttention })
    }
    @Test func oneThousandLostMutationResponsesRetainExactBytesAcrossReopenAndCommitOnce() async throws {
        let ship = ShipTransport(), dropped = DroppedMutationTransport(ship: ship), tokens = MemoryTokenStore()
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-retries-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        func make() throws -> ConnectClient { try ConnectClient(configuration: config, persistenceDirectory: root, tokens: tokens, transport: { _ in dropped }, automaticallySync: false) }
        var client = try make()
        let account = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        let id = UUID(); _ = try await client.put(collection: "lists", id: id, data: ["title": .string("Uncertain create")], expectedRevision: nil)
        for retry in 0..<1000 {
            do { try await client.syncOnce(); Issue.record("A withheld response unexpectedly reached the consumer") }
            catch let error as URLError { #expect(error.code == .networkConnectionLost) }
            if retry % 100 == 99 { client = try make(); #expect(try await client.resume() == account) }
        }
        try await client.syncOnce()
        #expect(try await client.recoveryDrafts().isEmpty)
        #expect(try await client.get(collection: "lists", id: id)?.revision.rawValue == "1")
        #expect(await ship.readCount() == 1)
        let bodies = await ship.bodies()
        #expect(bodies.count == 1001); #expect(bodies.allSatisfy { $0 == bodies.first })
    }
    @Test func temporaryHTTPFailuresDoNotRequireJSONProtocolBodies() throws {
        for status in [408, 429, 500, 502, 503, 504] {
            let failure = try ServerFailure(.init(status: status, body: Data("<html>temporarily unavailable</html>".utf8), retryAfter: nil))
            #expect(failure.status == status)
            #expect(!failure.message.contains("<html>"))
        }
    }
    @Test func interruptedPollPreservesCredentialsAndConfirmedDocuments() async throws {
        let ship = ShipTransport(); await ship.occupyPoll()
        let interrupted = InterruptedTransport(ship: ship), tokens = MemoryTokenStore()
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-reload-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        let client = try ConnectClient(configuration: config, persistenceDirectory: root, tokens: tokens, transport: { _ in interrupted }, automaticallySync: true)
        await client.setForeground(false)
        let account = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
        let id = UUID(); try await ship.remotePut(id: id, title: "Acknowledged before reload")
        try await client.syncOnce()
        await client.setForeground(true)
        for _ in 0..<200 {
            let state = await client.connectionStatus()
            if state == .offline || state == .needsAuthorization { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await client.connectionStatus() == .offline)
        #expect(await client.account() == account)
        #expect(try await client.documents(in: "lists").map(\.id) == [id])
        await client.setForeground(false)
        #expect(try await client.resume() == account)
        await client.setForeground(false)
    }
    @Test func malformedSuccessfulResponseStillFailsClosed() throws {
        let response = HTTPResponse(status: 200, body: Data("<html>not the protocol</html>".utf8), retryAfter: nil)
        #expect(throws: ConnectError.self) { _ = try response.json }
    }
}

actor UnavailableRefreshTransport: ConnectTransport {
    let ship: ShipTransport
    init(ship: ShipTransport) { self.ship = ship }
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse {
        let response = try await ship.send(path: path, method: method, body: body, token: token, form: form)
        if path == "/connect/oauth/token", String(decoding: body ?? Data(), as: UTF8.self).contains("grant_type=refresh_token") {
            return .init(status: 503, body: Data("Upstream became unavailable after refresh processing".utf8), retryAfter: 1)
        }
        return response
    }
}

actor DroppedMutationTransport: ConnectTransport {
    let ship: ShipTransport
    var remaining = 1000
    init(ship: ShipTransport) { self.ship = ship }
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse {
        let response = try await ship.send(path: path, method: method, body: body, token: token, form: form)
        if path == "/connect/v1/mutations", response.status == 200, remaining > 0 { remaining -= 1; throw URLError(.networkConnectionLost) }
        return response
    }
}
