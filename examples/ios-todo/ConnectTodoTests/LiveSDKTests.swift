import Foundation
import Testing
@testable import UrbitConnect

@MainActor private final class LoadControl: AuthorizationPresenter {
    private let url: URL
    private let token: String
    init() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CONNECT_TEST_CONTROL_PATH"])
        let info = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: String])
        let rawURL = try #require(info["url"])
        url = try #require(URL(string: rawURL)); token = try #require(info["token"])
    }
    func call(_ action: String, _ extra: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: extra.merging(["action": action]) { _, new in new })
        let (bytes, response) = try await URLSession.shared.data(for: request)
        try #require((response as? HTTPURLResponse)?.statusCode == 200)
        return try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let result = try await call("authorize-load", ["url": url.absoluteString])
        let callback = try #require(result["callback"] as? String)
        return try #require(URL(string: callback))
    }
}
private actor DroppingTransport: ConnectTransport {
    let actual: HTTPTransport
    var fault: String?
    var refreshes = 0
    init() throws { actual = try HTTPTransport(origin: URL(string: ProcessInfo.processInfo.environment["CONNECT_TEST_ORIGIN"]!)!) }
    func drop(_ value: String) { fault = value }
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse {
        let response = try await actual.send(path: path, method: method, body: body, token: token, form: form)
        let refresh = path == "/connect/oauth/token" && String(decoding: body ?? Data(), as: UTF8.self).contains("grant_type=refresh_token")
        if refresh { refreshes += 1 }
        if (fault == "write" && path == "/connect/v1/mutations") || (fault == "snapshot" && path.hasPrefix("/connect/v1/snapshots/") && method == "GET") || (fault == "refresh" && refresh) {
            fault = nil; throw URLError(.networkConnectionLost)
        }
        return response
    }
}
private final class LiveClock: @unchecked Sendable {
    let lock = NSLock(); private var time = Date()
    func now() -> Date { lock.withLock { time } }
    func advance() { lock.withLock { time = time.addingTimeInterval(700) } }
}
struct LiveSDKTests {
    @Test @MainActor func testRealShipRetryInterruptedSnapshotAndThousandDocumentHydration() async throws {
        let control = try LoadControl(); _ = try await control.call("seed-load", ["count": 0])
        let transport = try DroppingTransport(), clock = LiveClock(), tokens = KeychainTokenStore(service: "connect.acceptance." + UUID().uuidString)
        let directory = FileManager.default.temporaryDirectory.appending(path: "connect-live-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = try ConnectConfiguration(clientID: "connect-load-test", redirectURI: URL(string: "org.example.connect.load:/callback")!)
        func make(automatic: Bool = false) throws -> ConnectClient { try .init(configuration: config, persistenceDirectory: directory, tokens: tokens, transport: { _ in transport }, clock: { clock.now() }, automaticallySync: automatic) }
        let client = try make(); _ = try await client.connect(to: URL(string: ProcessInfo.processInfo.environment["CONNECT_TEST_ORIGIN"]!)!, presentation: control)
        var deep: JSONObject = ["leaf": .string("Deep document")]
        for _ in 0..<15 { deep = ["child": .object(deep)] }
        let id = UUID(); _ = try await client.put(collection: "lists", id: id, data: deep, expectedRevision: nil)
        await transport.drop("write")
        await #expect(throws: URLError.self) { try await client.syncOnce() }
        let reopened = try make(); _ = try await reopened.resume(); try await reopened.syncOnce()
        #expect(try await reopened.documents(in: "lists").count == 1)
        #expect(try await reopened.pendingForTesting().isEmpty)
        #expect(try await reopened.get(collection: "lists", id: id)?.data == deep)
        #expect(try await reopened.get(collection: "lists", id: id)?.revision == Revision("1"))
        _ = try await control.call("seed-load", ["count": 1000])
        _ = try await reopened.connect(to: URL(string: ProcessInfo.processInfo.environment["CONNECT_TEST_ORIGIN"]!)!, presentation: control)
        let realHost = ProcessInfo.processInfo.environment["CONNECT_TEST_REAL_QUALIFICATION"] == "1"
        if realHost { _ = try await control.call("network-profile", ["profile": "100ms-1percent"]) }
        await transport.drop("snapshot")
        await #expect(throws: URLError.self) { try await reopened.syncOnce() }
        #expect(try await reopened.documents(in: "lists").isEmpty)
        let start = Date(); try await reopened.syncOnce(); let seconds = Date().timeIntervalSince(start)
        let documents = try await reopened.documents(in: "lists").count
        try #require(documents == 1000); try #require(seconds < (realHost ? 30 : 10))
        var measurement: [String: Any] = ["seconds": seconds, "documents": documents]
        if realHost {
            let remoteID = try #require(try await reopened.documents(in: "lists").first?.id)
            let automatic = try make(automatic: true)
            do {
            _ = try await automatic.resume()
            let stream = await automatic.observe(collection: "lists")
            var ready = false, visibleAt: Date?
            let observer = Task { @MainActor in
                for await state in stream {
                    ready = state.connection == .online && state.hydrated
                    if state.documents.contains(where: { $0.id == remoteID && $0.data["title"] == .string("Remote visibility check") }) { visibleAt = Date(); return }
                }
            }
            defer { observer.cancel() }
            let readyDeadline = Date().addingTimeInterval(15)
            while !ready && Date() < readyDeadline { try await Task.sleep(for: .milliseconds(20)) }
            try #require(ready)
            let visibilityStart = Date()
            _ = try await control.call("mutate-load", ["id": remoteID.uuidString.lowercased()])
            while visibleAt == nil && Date().timeIntervalSince(visibilityStart) < 5 { try await Task.sleep(for: .milliseconds(20)) }
            let seen = try #require(visibleAt), visibility = seen.timeIntervalSince(visibilityStart)
            try #require(visibility < 5)
            measurement["visibilitySeconds"] = visibility
            } catch {
                await automatic.setForeground(false)
                throw error
            }
            await automatic.setForeground(false)
            _ = try await reopened.resume()
        }
        clock.advance(); await transport.drop("refresh")
        do { try await reopened.syncOnce() } catch { }
        #expect(await reopened.connectionStatus() == .needsAuthorization)
        let afterRefreshLoss = try make(); _ = try await afterRefreshLoss.resume()
        #expect(await afterRefreshLoss.connectionStatus() == .needsAuthorization)
        #expect(await transport.refreshes == 1)
        try? await afterRefreshLoss.disconnect()
        _ = try await control.call("record-sdk-load", measurement)
    }
}
