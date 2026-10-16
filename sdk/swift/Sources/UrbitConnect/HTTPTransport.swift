import Foundation

struct HTTPResponse: Sendable {
    let status: Int
    let body: Data
    let retryAfter: TimeInterval?
    var json: JSONObject {
        get throws {
            guard let object = try JSONValue.parse(body, maxDepth: 24).objectValue else { throw ConnectError.invalidJSON("Expected an object response") }
            return object
        }
    }
}
protocol ConnectTransport: Sendable {
    func send(path: String, method: String, body: Data?, token: String?, form: Bool) async throws -> HTTPResponse
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor HTTPTransport: ConnectTransport {
    let origin: URL
    private let session: URLSession
    init(origin: URL) throws {
        self.origin = try Self.validateOrigin(origin)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 35; config.timeoutIntervalForResource = 45
        session = URLSession(configuration: config, delegate: RedirectGuard(origin: origin), delegateQueue: nil)
    }
    static func validateOrigin(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/", (components.port ?? 443) > 0, (components.port ?? 443) <= 65535 else { throw ConnectError.invalidOrigin }
        components.scheme = "https"; components.host = host.lowercased(); components.path = ""
        guard let result = components.url else { throw ConnectError.invalidOrigin }; return result
    }
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == "https" && b.scheme?.lowercased() == "https" &&
        a.host?.lowercased() == b.host?.lowercased() && (a.port ?? 443) == (b.port ?? 443) &&
        a.user == nil && a.password == nil && b.user == nil && b.password == nil
    }
    func send(path: String, method: String = "GET", body: Data? = nil, token: String? = nil, form: Bool = false) async throws -> HTTPResponse {
        guard path.hasPrefix("/connect/"), !path.contains(".."), let url = URL(string: path, relativeTo: origin)?.absoluteURL, Self.sameOrigin(url, origin) else { throw ConnectError.invalidOrigin }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(form ? "application/x-www-form-urlencoded" : "application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, let finalURL = response.url, Self.sameOrigin(finalURL, origin) else { throw ConnectError.protocolMismatch }
        if (300..<400).contains(response.statusCode) { throw ConnectError.invalidOrigin }
        var bytes = Data()
        for try await byte in stream {
            bytes.append(byte)
        }
        return .init(status: response.statusCode, body: bytes, retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
    }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(values.keys.sorted().map { key in key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + values[key]!.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
    }
}
