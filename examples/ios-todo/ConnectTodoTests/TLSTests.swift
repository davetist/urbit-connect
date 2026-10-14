import Foundation
import Testing
@testable import UrbitConnect

struct TLSTests {
    @Test func testUnreachableEndpointReturnsNetworkFailure() async throws {
        let transport = try HTTPTransport(origin: URL(string: ProcessInfo.processInfo.environment["CONNECT_TEST_UNREACHABLE_ORIGIN"]!)!)
        let start = Date()
        do {
            _ = try await transport.send(path: "/connect/v1/info", method: "GET", body: nil, token: nil, form: false)
            Issue.record("An unreachable endpoint returned a successful response")
        } catch is URLError {
            #expect(Date().timeIntervalSince(start) < 46)
        }
    }
    @Test func testNormalTLSReachesActualShip() async throws {
        let transport = try HTTPTransport(origin: URL(string: ProcessInfo.processInfo.environment["CONNECT_TEST_ORIGIN"]!)!)
        let response = try await transport.send(path: "/connect/v1/info", method: "GET", body: nil, token: nil, form: false)
        #expect(response.status == 200)
        #expect(try response.json["ship"] == .string("~zod"))
    }
    @Test func testUntrustedAndWrongHostnameCertificatesFail() async throws {
        for name in ["CONNECT_TEST_UNTRUSTED_ORIGIN", "CONNECT_TEST_WRONG_HOST_ORIGIN"] {
            let transport = try HTTPTransport(origin: URL(string: ProcessInfo.processInfo.environment[name]!)!)
            do {
                _ = try await transport.send(path: "/connect/v1/info", method: "GET", body: nil, token: nil, form: false)
                Issue.record("Invalid TLS certificate was accepted")
            } catch let error as URLError {
                #expect([URLError.serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .secureConnectionFailed].contains(error.code))
            }
        }
    }
    @Test func testExpiredCertificateFromTrustedIssuerFails() async throws {
        let transport = try HTTPTransport(origin: URL(string: ProcessInfo.processInfo.environment["CONNECT_TEST_EXPIRED_ORIGIN"]!)!)
        do {
            _ = try await transport.send(path: "/connect/v1/info", method: "GET", body: nil, token: nil, form: false)
            Issue.record("An expired TLS certificate was accepted")
        } catch let error as URLError {
            #expect(error.code == .serverCertificateHasBadDate || error.code == .serverCertificateUntrusted)
        }
    }
}
