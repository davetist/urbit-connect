import Foundation
import XCTest

@MainActor final class NativeHarness {
    private let endpoint: URL
    private let token: String
    init() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["CONNECT_TEST_CONTROL_PATH"])
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: String])
        endpoint = try XCTUnwrap(URL(string: XCTUnwrap(values["url"]))); token = try XCTUnwrap(values["token"])
    }
    func call(_ action: String, extra: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: extra.merging(["action": action]) { _, new in new })
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HarnessError.rejected }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func documents() async throws -> [[String: Any]] {
        let result = try await call("documents")
        return try XCTUnwrap(result["documents"] as? [[String: Any]])
    }
    func document(titled title: String) async throws -> [String: Any] {
        let rows = try await documents()
        return try XCTUnwrap(rows.first { ($0["data"] as? [String: Any])?["title"] as? String == title })
    }
    func replace(_ document: [String: Any], data: [String: Any]) async throws {
        _ = try await call("mutate", extra: ["mutation": ["requestId": UUID().uuidString.lowercased(), "operations": [["type": "put", "collection": "lists", "id": try XCTUnwrap(document["id"]), "expectedRevision": try XCTUnwrap(document["revision"]), "data": data]]]])
    }
    enum HarnessError: Error { case rejected }
}
