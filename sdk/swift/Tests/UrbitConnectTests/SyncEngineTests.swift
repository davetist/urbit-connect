import Foundation
import Testing
@testable import UrbitConnect

@MainActor final class TestPresenter: AuthorizationPresenter {
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        return URL(string: "org.example.connect.test:/oauth/callback?code=test-code&state=" + state)!
    }
}
actor ShipTransport: ConnectTransport {
    var documents: [UUID: ConnectDocument] = [:]
    var networkDown = false
    func disconnectNetwork() { networkDown = true }
    var busyPoll = false
    var pollCount = 0
    func occupyPoll() { busyPoll = true }
    var revision = 0
    var journal: [(Int, [JSONValue])] = []
    var receivedBodies: [Data] = []
    var receipts: [String: HTTPResponse] = [:]
    var loseNextSuccess = false
    var revoked = false
    var epoch = "1"
    var snapshotExpired = false
    var gap = false
    var rejectWrites = false
    var loseRefresh = false
    var refreshCount = 0
    var infoCount = 0
    var pauseRevoke = false
    var pausedRevoke: CheckedContinuation<Void, Never>?
    var pauseRefresh = false
    var pausedRefresh: CheckedContinuation<Void, Never>?
    func pauseNextRevoke() { pauseRevoke = true }
    func releaseRevoke() { pausedRevoke?.resume(); pausedRevoke = nil }
    func pauseNextRefresh() { pauseRefresh = true }
    func releaseRefresh() { pausedRefresh?.resume(); pausedRefresh = nil }
    var snapshotCount = 0
    var partialSnapshot = false
    var changedInstance = false
    var changedIssuer = false
    var pauseWrite = false
    var pausedWrite: CheckedContinuation<Void, Never>?
    var pausedObserver: CheckedContinuation<Void, Never>?
    func rejectMutations() { rejectWrites = true }
    func loseRefreshResponse() { loseRefresh = true }
    func expireSnapshotOnce() { snapshotExpired = true }
    func replaceInstance() { changedInstance = true }
    func replaceIssuer() { changedIssuer = true }
    func refreshes() -> Int { refreshCount }
    func snapshots() -> Int { snapshotCount }
    func pauseNextWrite() { pauseWrite = true }
    func waitForPausedWrite() async {
        if pausedWrite != nil { return }
        await withCheckedContinuation { pausedObserver = $0 }
    }
    func releaseWrite() { pausedWrite?.resume(); pausedWrite = nil }
    let account: JSONObject
    init(origin: String = "https://ship.example", instance: String = "instance") {
        account = ["issuer": .string(origin + "/connect"), "instanceId": .string(instance), "ship": .string("~zod"), "syncEpoch": .string("1")]
    }
    let grant: JSONObject = ["id": .string("session"), "clientId": .string("connect-test"), "namespace": .string("app-1"), "namespaceEpoch": .string("1"), "scopes": .array([.string("documents:read"), .string("documents:write"), .string("documents:delete")]), "sessionId": .string("session")]
    func loseResponse() { loseNextSuccess = true }
    func revoke() { revoked = true }
    func changeEpoch() { epoch = "2" }
    func setGap() { gap = true }
    func readCount() -> Int { documents.count }
    func bodies() -> [Data] { receivedBodies }
    func remotePut(id: UUID, title: String) throws {
        revision += 1
        documents[id] = .init(id: id, collection: "lists", data: ["title": .string(title)], revision: try Revision(String(revision)), updatedAt: "2026-10-12T00:00:00Z")
        journal.append((revision, [.object(["document": .object(documents[id]!.wire), "deleted": .bool(false)])]))
    }
    func remoteDelete(id: UUID) {
        revision += 1; documents.removeValue(forKey: id)
        journal.append((revision, [.object(["id": .string(id.uuidString.lowercased()), "collection": .string("lists"), "revision": .string(String(revision)), "deleted": .bool(true)])]))
    }
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse {
        if networkDown { throw URLError(.cannotConnectToHost) }
        func result(_ status: Int = 200, _ wire: JSONObject) throws -> HTTPResponse { .init(status: status, body: try JSONValue.object(wire).encoded(), retryAfter: nil) }
        func error(_ status: Int, _ code: String) throws -> HTTPResponse { try result(status, ["error": .object(["code": .string(code), "message": .string(code), "requestId": .null])]) }
        if path == "/connect/v1/info" {
            infoCount += 1
            var info = account; info["syncEpoch"] = .string(epoch); info["protocolVersion"] = .number("1"); info["configured"] = .bool(true); info["development"] = .bool(true)
            if changedInstance { info["instanceId"] = .string("replacement") }
            if changedIssuer { info["issuer"] = .string("https://other.example/connect") }
            return try result(200, info)
        }
        if path == "/connect/oauth/token" {
            if String(decoding: body ?? Data(), as: UTF8.self).contains("grant_type=refresh_token") {
                refreshCount += 1
                if pauseRefresh { pauseRefresh = false; await withCheckedContinuation { pausedRefresh = $0 } }
                if loseRefresh { loseRefresh = false; throw URLError(.networkConnectionLost) }
            }
            if revoked { return try result(400, ["error": .string("invalid_grant")]) }
            return try result(200, ["access_token": .string("test-access"), "refresh_token": .string("test-refresh"), "expires_in": .number("600"), "token_type": .string("Bearer"), "grant": .object(grant)])
        }
        if revoked { return try error(401, "invalid_token") }
        if path == "/connect/v1/identity" { var current = account; current["syncEpoch"] = .string(epoch); return try result(200, ["account": .object(current), "grant": .object(grant)]) }
        if path == "/connect/oauth/revoke" {
            if pauseRevoke { pauseRevoke = false; await withCheckedContinuation { pausedRevoke = $0 } }
            revoked = true; return try result(200, ["revoked": .bool(true)])
        }
        if path.hasPrefix("/connect/v1/snapshots") {
            if method == "POST" { snapshotCount += 1 }
            if snapshotExpired && !partialSnapshot {
                partialSnapshot = true
                return try result(200, ["snapshotId": .string("snapshot"), "atCursor": .string("\(epoch):1:\(revision)"), "documents": .array([]), "nextPage": .string("100")])
            }
            if snapshotExpired && method == "GET" { snapshotExpired = false; return try error(410, "snapshot_expired") }
            return try result(200, ["snapshotId": .string("snapshot"), "atCursor": .string("\(epoch):1:\(revision)"), "documents": .array(documents.values.sorted { $0.id.uuidString < $1.id.uuidString }.map { .object($0.wire) }), "nextPage": .null])
        }
        if path.hasPrefix("/connect/v1/changes") {
            if path.contains("wait=25") { pollCount += 1; if busyPoll { return try error(429, "poll_capacity") } }
            if gap { gap = false; return try error(410, "cursor_expired") }
            let query = URLComponents(string: "https://ship.example" + path)?.queryItems ?? []
            let after = query.first { $0.name == "after" }?.value ?? "1:1:0"
            let since = Int(after.split(separator: ":").last ?? "0") ?? 0
            let batches = journal.filter { $0.0 > since }.map { JSONValue.object(["revision": .string(String($0.0)), "changes": .array($0.1)]) }
            return try result(200, ["batches": .array(batches), "nextCursor": .string("\(epoch):1:\(revision)"), "hasMore": .bool(false)])
        }
        if path == "/connect/v1/mutations", let body {
            receivedBodies.append(body)
            if rejectWrites { return try error(413, "document_too_large") }
            if pauseWrite {
                pauseWrite = false
                await withCheckedContinuation { continuation in
                    pausedWrite = continuation; pausedObserver?.resume(); pausedObserver = nil
                }
            }
            let input = try #require(JSONValue.parse(body).objectValue)
            let requestID = try input.string("requestId")
            if let receipt = receipts[requestID] { return receipt }
            let op = try #require(try input.array("operations").first?.objectValue)
            let id = try #require(UUID(uuidString: try op.string("id"))), expected = op["expectedRevision"]?.stringValue
            if expected != documents[id]?.revision.rawValue {
                var detail: JSONObject = ["code": .string("conflict"), "message": .string("conflict"), "requestId": .string(requestID), "current": documents[id].map { .object($0.wire) } ?? .null, "currentRevision": documents[id].map { .string($0.revision.rawValue) } ?? .null, "deleted": .bool(documents[id] == nil)]
                detail["id"] = .string(id.uuidString.lowercased()); detail["collection"] = .string("lists")
                return try result(409, ["error": .object(detail)])
            }
            revision += 1
            let deleted = try op.string("type") == "delete"
            if deleted { documents.removeValue(forKey: id) }
            else { documents[id] = try .init(id: id, collection: op.string("collection"), data: op.object("data"), revision: Revision(String(revision)), updatedAt: "2026-10-12T00:00:00Z") }
            let change: JSONValue = deleted ? .object(["id": .string(id.uuidString.lowercased()), "collection": .string("lists"), "revision": .string(String(revision)), "deleted": .bool(true)]) : .object(["document": .object(documents[id]!.wire), "deleted": .bool(false)])
            journal.append((revision, [change]))
            let entry: JSONObject = ["id": .string(id.uuidString.lowercased()), "collection": .string("lists"), "revision": .string(String(revision)), "deleted": .bool(deleted)]
            let receipt = try result(200, ["revision": .string(String(revision)), "results": .array([.object(entry)])])
            receipts[requestID] = receipt
            if loseNextSuccess { loseNextSuccess = false; throw URLError(.networkConnectionLost) }
            return receipt
        }
        return try error(404, "not_found")
    }
}

struct SyncEngineTests {
    @Test func testDevelopmentIdentitySurvivesCredentialPersistence() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore()
        let (client, directory) = try make(ship, tokens: tokens)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client)
        #expect(await client.account()?.isDevelopment == true)
        let (reopened, _) = try make(ship, directory: directory, tokens: tokens)
        #expect(try await reopened.resume()?.isDevelopment == true)
    }
    @Test func testNetworkFailureDuringPollBackoffPublishesOfflineWithDraft() async throws {
        let ship = ShipTransport(); await ship.occupyPoll()
        let (client, directory) = try make(ship, automaticallySync: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client)
        for _ in 0..<100 {
            if await ship.pollCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await ship.disconnectNetwork()
        _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Offline draft")], expectedRevision: nil)
        for _ in 0..<200 {
            if await client.connectionStatus() == .offline { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await client.connectionStatus() == .offline)
        #expect(try await client.pendingForTesting().count == 1)
        await client.setForeground(false)
    }
    @Test func testOldPollAfterAppRestartDoesNotReportDataOffline() async throws {
        let ship = ShipTransport(); await ship.occupyPoll()
        let (client, directory) = try make(ship, automaticallySync: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client)
        for _ in 0..<100 {
            if await ship.pollCount > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await ship.pollCount > 0)
        #expect(await client.connectionStatus() == .online)
        await client.setForeground(false)
    }
    @Test func testRevokedRefreshCannotResumeSync() async throws {
        let ship = ShipTransport(), clock = TestClock(), tokens = MemoryTokenStore()
        let (client, directory) = try make(ship, tokens: tokens, clock: clock)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); try await client.syncOnce()
        _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Recover me")], expectedRevision: nil)
        clock.advance(700); await ship.revoke()
        do { try await client.syncOnce() } catch { }
        #expect(await client.connectionStatus() == .revoked)
        #expect(await ship.refreshes() == 1)
        let (reopened, _) = try make(ship, directory: directory, tokens: tokens, clock: clock)
        #expect(try await reopened.resume() == nil)
        #expect(try await reopened.recoveryDrafts().count == 1)
        #expect(await ship.refreshes() == 1)
    }
    @Test func testConcurrentRequestsSerializeRefresh() async throws {
        let ship = ShipTransport(), clock = TestClock()
        let (client, directory) = try make(ship, clock: clock)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); try await client.syncOnce(); clock.advance(700)
        async let first: Void = client.syncOnce()
        async let second: Void = client.syncOnce()
        _ = try await (first, second)
        #expect(await ship.refreshes() == 1)
        #expect(await client.connectionStatus() == .online)
    }
    @Test func testMissingCredentialsClearConfirmedAndRetainDrafts() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore()
        let (client, directory) = try make(ship, tokens: tokens)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client)
        let id = UUID(); try await ship.remotePut(id: id, title: "Private confirmed")
        try await client.syncOnce()
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("Unsent draft")], expectedRevision: Revision("1"))
        let selected = try String(contentsOf: directory.appending(path: "selected-" + Data("connect-test".utf8).sha256Hex + ".txt"), encoding: .utf8)
        try tokens.delete(key: selected)
        #expect(try await client.resume() == nil)
        #expect(try await client.documents(in: "lists").isEmpty)
        let drafts = try await client.pendingForTesting()
        #expect(drafts.count == 1)
        #expect(drafts.first?.status == .needsAttention)
        do {
            _ = try await client.put(collection: "lists", id: UUID(), data: [:], expectedRevision: nil)
            Issue.record("Missing credentials still allowed a new mutation")
        } catch ConnectError.notConnected { }
    }
    func make(_ transport: ShipTransport, directory: URL? = nil, tokens: MemoryTokenStore = .init(), clock: TestClock? = nil, automaticallySync: Bool = false) throws -> (ConnectClient, URL) {
        let directory = directory ?? FileManager.default.temporaryDirectory.appending(path: "connect-sync-" + UUID().uuidString)
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        return (try ConnectClient(configuration: config, persistenceDirectory: directory, tokens: tokens, transport: { _ in transport }, clock: { clock?.now() ?? Date() }, automaticallySync: automaticallySync), directory)
    }
    func connect(_ client: ConnectClient) async throws {
        _ = try await client.connect(to: URL(string: "https://ship.example")!, presentation: TestPresenter())
    }
    @Test func testLostSuccessResponseCommitsOnceAndOutboxSurvivesReopen() async throws {
        let ship = ShipTransport(), tokens = MemoryTokenStore(); let (client, directory) = try make(ship, tokens: tokens)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client)
        let id = UUID(); _ = try await client.put(collection: "lists", id: id, data: ["title": .string("Draft")], expectedRevision: nil)
        await ship.loseResponse()
        do { try await client.syncOnce() } catch { }
        #expect(await ship.readCount() == 1)
        let (reopened, _) = try make(ship, directory: directory, tokens: tokens)
        _ = try await reopened.resume(); try await reopened.syncOnce()
        #expect(await ship.readCount() == 1)
        #expect(try await reopened.pendingForTesting().isEmpty)
        #expect(try await reopened.get(collection: "lists", id: id)?.data["title"] == .string("Draft"))
        let sent = await ship.bodies(); #expect(sent.count >= 2); #expect(sent.first == sent.last)
    }
    @Test func testConflictPreservesBothVersions() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); let id = UUID(); try await ship.remotePut(id: id, title: "Base"); try await client.syncOnce()
        let revision = try #require(try await client.get(collection: "lists", id: id)?.revision)
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("My draft")], expectedRevision: revision)
        try await ship.remotePut(id: id, title: "Remote change"); try await client.syncOnce()
        let pending = try #require(try await client.pendingForTesting().first)
        #expect(pending.status == .conflict); #expect(pending.draft?["title"] == .string("My draft")); #expect(pending.current?.data["title"] == .string("Remote change"))
    }
    @Test func testRevocationRetainsRecoverableDraftAndClearsConfirmedData() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); let id = UUID(); try await ship.remotePut(id: id, title: "Base"); try await client.syncOnce()
        let revision = try #require(try await client.get(collection: "lists", id: id)?.revision)
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("Unsent")], expectedRevision: revision)
        await ship.revoke(); do { try await client.syncOnce() } catch { }
        #expect(try await client.documents(in: "lists").isEmpty)
        #expect(try await client.recoveryDrafts().first?.draft?["title"] == .string("Unsent"))
    }
    @Test func testRestoreEpochRequiresReauthorization() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); await ship.changeEpoch()
        await #expect(throws: ConnectError.self) { try await client.syncOnce() }
    }
    @Test func testEditWhileWriteInFlightPreservesNewestOverlay() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); let id = UUID()
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("First draft")], expectedRevision: nil)
        await ship.pauseNextWrite()
        let first = Task { try await client.syncOnce() }
        await ship.waitForPausedWrite()
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("Newer draft")], expectedRevision: nil)
        await ship.releaseWrite(); try await first.value
        #expect(try await client.pendingForTesting().last?.draft?["title"] == .string("Newer draft"))
        try await client.syncOnce()
        #expect(try await client.get(collection: "lists", id: id)?.data["title"] == .string("Newer draft"))
        #expect(try await client.pendingForTesting().isEmpty); #expect(await ship.readCount() == 1)
    }
    @Test func testRemoteDeleteDoesNotResurrectDraft() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); let id = UUID(); try await ship.remotePut(id: id, title: "Base"); try await client.syncOnce()
        let revision = try #require(try await client.get(collection: "lists", id: id)?.revision)
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("My draft")], expectedRevision: revision)
        await ship.remoteDelete(id: id); try await client.syncOnce()
        #expect(await ship.readCount() == 0); #expect(try await client.get(collection: "lists", id: id) == nil)
        #expect(try await client.pendingForTesting().first?.status == .conflict)
    }
    @Test func testGapResnapshotsWithoutDroppingDraft() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); let id = UUID(); try await ship.remotePut(id: id, title: "Base"); try await client.syncOnce()
        let revision = try #require(try await client.get(collection: "lists", id: id)?.revision)
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("My draft")], expectedRevision: revision)
        try await ship.remotePut(id: id, title: "Remote"); await ship.setGap(); try await client.syncOnce()
        #expect(await ship.snapshots() == 2)
        #expect(try await client.pendingForTesting().first?.draft?["title"] == .string("My draft"))
        #expect(try await client.get(collection: "lists", id: id)?.data["title"] == .string("Remote"))
    }
    @Test func testExpiredSnapshotRestarts() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); let id = UUID(); try await ship.remotePut(id: id, title: "Kept")
        await ship.expireSnapshotOnce(); try await client.syncOnce()
        #expect(await ship.snapshots() == 2); #expect(try await client.get(collection: "lists", id: id)?.data["title"] == .string("Kept"))
    }
    @Test func testMutationOlderThan30DaysNeedsReview() async throws {
        let ship = ShipTransport(), clock = TestClock(); let (client, directory) = try make(ship, clock: clock); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Old draft")], expectedRevision: nil)
        clock.advance(31 * 86400); try await client.syncOnce()
        #expect(await ship.bodies().isEmpty); #expect(try await client.pendingForTesting().first?.status == .needsAttention)
    }
    @Test func testPermanentRejectionKeepsDraftWithoutRetryLoop() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); _ = try await client.put(collection: "lists", id: UUID(), data: ["title": .string("Draft")], expectedRevision: nil)
        await ship.rejectMutations(); try await client.syncOnce(); try await client.syncOnce()
        #expect(await ship.bodies().count == 1); #expect(try await client.pendingForTesting().first?.status == .needsAttention)
    }
    @Test func testAmbiguousRefreshIsNeverReplayedAfterReopen() async throws {
        let ship = ShipTransport(), clock = TestClock(), tokens = MemoryTokenStore()
        let (client, directory) = try make(ship, tokens: tokens, clock: clock); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); try await client.syncOnce(); clock.advance(700); await ship.loseRefreshResponse()
        do { try await client.syncOnce() } catch { }
        #expect(await client.connectionStatus() == .needsAuthorization); #expect(await ship.refreshes() == 1)
        let (reopened, _) = try make(ship, directory: directory, tokens: tokens, clock: clock); _ = try await reopened.resume()
        do { try await reopened.syncOnce() } catch { }
        #expect(await reopened.connectionStatus() == .needsAuthorization); #expect(await ship.refreshes() == 1)
    }
    @Test func testIssuerAndInstanceChangesRequireExplicitPairing() async throws {
        for changeIssuer in [false, true] {
            let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
            try await connect(client)
            if changeIssuer { await ship.replaceIssuer() } else { await ship.replaceInstance() }
            do { try await client.syncOnce() } catch { }
            #expect(await client.connectionStatus() == .needsAuthorization)
        }
    }

    @Test func testConflictResolutionDoesNotOverwriteANewerUnseenVersion() async throws {
        let ship = ShipTransport(); let (client, directory) = try make(ship); defer { try? FileManager.default.removeItem(at: directory) }
        try await connect(client); let id = UUID(); try await ship.remotePut(id: id, title: "Base"); try await client.syncOnce()
        let revision = try #require(try await client.get(collection: "lists", id: id)?.revision)
        _ = try await client.put(collection: "lists", id: id, data: ["title": .string("My draft")], expectedRevision: revision)
        try await ship.remotePut(id: id, title: "Version shown in conflict"); try await client.syncOnce()
        let conflict = try #require(try await client.pendingForTesting().first)
        let shown = try #require(conflict.current?.revision)
        try await ship.remotePut(id: id, title: "Newer remote version"); try await client.syncOnce()
        _ = try await client.resolveConflict(conflict.id, resolution: .retryWithCurrent)
        #expect(try await client.pendingForTesting().first?.expected == shown)
        try await client.syncOnce()
        #expect(try await client.pendingForTesting().first?.status == .conflict)
    }

}
