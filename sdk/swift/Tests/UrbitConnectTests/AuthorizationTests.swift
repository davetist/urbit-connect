import Foundation
import Testing
@testable import UrbitConnect

struct AuthorizationTests {
    func request() throws -> AuthorizationRequest {
        try .init(configuration: .init(clientID: "connect-todo-prototype", redirectURI: URL(string: "org.example.urbitconnect.todo:/oauth/callback")!), origin: URL(string: "https://ship.example")!, verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wWFOEjXk", state: "expected-state")
    }
    @Test func testStateAndPKCEBinding() throws {
        let configuration = try ConnectConfiguration(clientID: "connect-todo-prototype", redirectURI: URL(string: "org.example.urbitconnect.todo:/oauth/callback")!)
        let request = try AuthorizationRequest(configuration: configuration, origin: URL(string: "https://ship.example")!, verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "expected-state")
        #expect(request.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(try request.code(from: URL(string: "org.example.urbitconnect.todo:/oauth/callback?code=secret&state=expected-state")!) == "secret")
        for callback in ["org.example.urbitconnect.todo:/oauth/callback?code=secret&state=wrong", "evil:/oauth/callback?code=secret&state=expected-state", "org.example.urbitconnect.todo:/different?code=secret&state=expected-state", "org.example.urbitconnect.todo:/oauth/callback?code=secret&state=expected-state&state=other", "org.example.urbitconnect.todo:/oauth/callback?error=access_denied&state=expected-state"] {
            #expect(throws: ConnectError.self) { try request.code(from: URL(string: callback)!) }
        }
    }
    @Test func testRejectsCrossOriginRedirectAndUnsafePairingURL() throws {
        let origin = URL(string: "https://ship.example")!
        #expect(!HTTPTransport.sameOrigin(origin, URL(string: "https://other.example")!))
        #expect(!HTTPTransport.sameOrigin(origin, URL(string: "http://ship.example")!))
        #expect(!HTTPTransport.sameOrigin(origin, URL(string: "https://ship.example:444")!))
        #expect(HTTPTransport.sameOrigin(origin, URL(string: "https://ship.example:443/connect/v1/info")!))
        for raw in ["http://ship.example", "https://user:password@ship.example", "https://ship.example/foo", "https://ship.example?token=x"] {
            #expect(throws: ConnectError.self) { try HTTPTransport.validateOrigin(URL(string: raw)!) }
        }
    }
}
