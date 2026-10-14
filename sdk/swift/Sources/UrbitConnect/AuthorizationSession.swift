import Foundation
import AuthenticationServices
import CryptoKit
import Security

public struct ConnectConfiguration: Sendable {
    public let clientID: String
    public let redirectURI: URL
    public let requestedScopes: [String]
    public init(clientID: String, redirectURI: URL, requestedScopes: [String] = ["documents:read", "documents:write", "documents:delete"]) throws {
        guard ConnectIdentifiers.collection(clientID), let scheme = redirectURI.scheme, scheme.contains("."),
              redirectURI.query == nil, redirectURI.fragment == nil, redirectURI.user == nil, redirectURI.password == nil,
              redirectURI.path.hasPrefix("/"), !requestedScopes.isEmpty,
              Set(requestedScopes).isSubset(of: ["documents:read", "documents:write", "documents:delete"]) else { throw ConnectError.invalidIdentifier }
        self.clientID = clientID; self.redirectURI = redirectURI; self.requestedScopes = Array(Set(requestedScopes)).sorted()
    }
}

@MainActor public protocol AuthorizationPresenter: Sendable {
    func authorize(url: URL, callbackScheme: String) async throws -> URL
}

/// Uses the system authentication browser. Browser cookies stay outside the SDK's network session.
@MainActor public final class SystemAuthorizationPresenter: NSObject, AuthorizationPresenter, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, any Error>?
    public init(anchor: ASPresentationAnchor) { self.anchor = anchor; super.init() }
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
    public func authorize(url: URL, callbackScheme: String) async throws -> URL {
        guard session == nil else { throw ConnectError.transport("Authorization is already in progress") }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let pending = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callback, error in
                    Task { @MainActor in
                        if let callback { self?.finish(.success(callback)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { self?.finish(.failure(ConnectError.authorizationCancelled)) }
                        else { self?.finish(.failure(error ?? ConnectError.unauthorized)) }
                    }
                }
                pending.presentationContextProvider = self
                pending.prefersEphemeralWebBrowserSession = true
                session = pending
                if Task.isCancelled { pending.cancel(); finish(.failure(CancellationError())) }
                else if !pending.start() { finish(.failure(ConnectError.transport("The system browser could not start"))) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.session?.cancel(); self?.finish(.failure(CancellationError()))
            }
        }
    }
    private func finish(_ result: Result<URL, any Error>) {
        let pending = continuation; continuation = nil; session = nil
        pending?.resume(with: result)
    }
}

struct AuthorizationRequest: Sendable {
    let verifier: String
    let state: String
    let configuration: ConnectConfiguration
    let origin: URL
    init(configuration: ConnectConfiguration, origin: URL, verifier: String? = nil, state: String? = nil) throws {
        self.configuration = configuration; self.origin = origin
        self.verifier = try verifier ?? Self.random(); self.state = try state ?? Self.random()
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ConnectError.transport("Secure random generation failed") }
        return Data(bytes).base64URL
    }
    var challenge: String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
    var url: URL {
        var parts = URLComponents(url: origin.appending(path: "connect/oauth/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "response_type", value: "code"), .init(name: "client_id", value: configuration.clientID), .init(name: "redirect_uri", value: configuration.redirectURI.absoluteString), .init(name: "scope", value: configuration.requestedScopes.joined(separator: " ")), .init(name: "state", value: state), .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"), .init(name: "device_label", value: "iOS app")]
        return parts.url!
    }
    func code(from callback: URL) throws -> String {
        guard var components = URLComponents(url: callback, resolvingAgainstBaseURL: false), components.fragment == nil else { throw ConnectError.unauthorized }
        let items = components.queryItems ?? []; components.query = nil
        guard components.url?.absoluteString == configuration.redirectURI.absoluteString else { throw ConnectError.unauthorized }
        var values: [String: String] = [:]
        for item in items {
            guard values[item.name] == nil, let value = item.value, ["code", "state", "error", "error_description"].contains(item.name) else { throw ConnectError.unauthorized }
            values[item.name] = value
        }
        guard let returnedState = values["state"], Self.equal(returnedState, state) else { throw ConnectError.unauthorized }
        if values["error"] != nil { throw ConnectError.authorizationDenied }
        guard let code = values["code"], !code.isEmpty, code.utf8.count <= 256 else { throw ConnectError.unauthorized }
        return code
    }
    private static func equal(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8), right = Array(b.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
