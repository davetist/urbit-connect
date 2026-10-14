import Foundation
import Testing
@testable import UrbitConnect

actor PreflightTransport: ConnectTransport {
    let response: HTTPResponse
    var paths: [String] = []
    init(_ response: HTTPResponse) { self.response = response }
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse {
        #expect(method == "GET" && body == nil && token == nil)
        paths.append(path); return response
    }
}
struct PreflightTests {
    @Test func managerAddressRequiresExplicitOriginConfirmation() throws {
        let parsed = try ConnectEndpoint(" https://SHIP.example:444/apps/connect/ ")
        #expect(parsed.origin.absoluteString == "https://ship.example:444")
        #expect(parsed.requiresConfirmation)
        #expect(try !ConnectEndpoint("https://ship.example/").requiresConfirmation)
        for raw in ["http://ship.example", "https://ship.example/other", "https://ship.example/apps/connect/?code=x", "https://user@ship.example/apps/connect/", "https://ship.example/apps/%63onnect/"] {
            #expect(throws: ConnectError.invalidOrigin) { try ConnectEndpoint(raw) }
        }
    }
    @Test func preflightIsReadOnlyAndPinsTheExpectedAccount() async throws {
        let origin = URL(string: "https://ship.example")!
        let wire: JSONObject = ["protocolVersion": .number("1"), "configured": .bool(true), "issuer": .string("https://ship.example/connect"), "instanceId": .string("instance"), "ship": .string("~zod"), "syncEpoch": .string("1")]
        let transport = PreflightTransport(.init(status: 200, body: try JSONValue.object(wire).encoded(), retryAfter: nil))
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-preflight-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        let client = try ConnectClient(configuration: config, persistenceDirectory: root, tokens: MemoryTokenStore(), transport: { _ in transport }, automaticallySync: false)
        let account = try await client.preflight(origin: origin)
        #expect(account.instanceId == "instance")
        var wrong = wire; wrong["instanceId"] = .string("different")
        await #expect(throws: ConnectError.accountChanged) { try await client.preflight(origin: origin, expected: ConnectAccount(wire: wrong)) }
        #expect(await client.account() == nil)
        #expect(await transport.paths == ["/connect/v1/info", "/connect/v1/info"])
    }
    @Test func missingDeskSetupAndVersionHaveDistinctResults() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-preflight-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try ConnectConfiguration(clientID: "connect-test", redirectURI: URL(string: "org.example.connect.test:/oauth/callback")!)
        for (status, body, expected) in [(404, "<html>not installed</html>", ConnectError.missingDesk), (200, "{\"protocolVersion\":1,\"configured\":false}", .notConfigured), (200, "{\"protocolVersion\":2,\"configured\":true}", .unsupportedProtocol)] {
            let transport = PreflightTransport(.init(status: status, body: Data(body.utf8), retryAfter: nil))
            let client = try ConnectClient(configuration: config, persistenceDirectory: root, tokens: MemoryTokenStore(), transport: { _ in transport }, automaticallySync: false)
            await #expect(throws: expected) { try await client.preflight(origin: URL(string: "https://ship.example")!) }
        }
    }
}
