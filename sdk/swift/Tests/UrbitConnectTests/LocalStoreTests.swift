import Foundation
import Testing
@testable import UrbitConnect

struct LocalStoreTests {
    func location() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appending(path: "cache.sqlite")
    }
    func mutation() throws -> StoredMutation {
        var value = StoredMutation(id: .init(rawValue: UUID()), collection: "lists", documentID: UUID(), draft: ["title": .string("Offline edit")], expected: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000), status: .pending)
        value.body = try value.requestBody(); return value
    }
    @Test func testMaximumDepthDocumentSurvivesOutboxAndConfirmedStorage() throws {
        var data: JSONObject = ["leaf": .string("deep")]
        for _ in 0..<15 { data = ["child": .object(data)] }
        _ = try JSONValue.object(data).encoded(maxBytes: 16_384)
        var queued = StoredMutation(id: .init(rawValue: UUID()), collection: "lists", documentID: UUID(), draft: data, expected: nil, createdAt: Date(), status: .pending)
        queued.body = try queued.requestBody()
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalStore(url: url); try store.enqueue(queued)
        let record = ConnectDocument(id: queued.documentID, collection: "lists", data: data, revision: try Revision("1"), updatedAt: "2026-10-12T00:00:00Z")
        try store.replaceSnapshot([record], cursor: "1:1:1")
        let reopened = try LocalStore(url: url)
        #expect(try reopened.mutations().first?.draft == data)
        #expect(try reopened.documents().first?.data == data)
    }
    @Test func testOutboxSurvivesReopenAndPreservesExactRequestBytes() throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let queued = try mutation()
        do { let store = try LocalStore(url: url); try store.enqueue(queued) }
        let reopened = try LocalStore(url: url)
        #expect(try reopened.mutations() == [queued])
        #expect(try reopened.mutations().first?.body == queued.body)
    }
    @Test func testCursorAndDocumentsCommitTogether() throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let record = ConnectDocument(id: UUID(), collection: "lists", data: ["title": .string("Confirmed")], revision: try Revision("9007199254740993"), updatedAt: "2026-10-12T00:00:00Z")
        do { let store = try LocalStore(url: url); try store.replaceSnapshot([record], cursor: "1:1:9007199254740993") }
        let reopened = try LocalStore(url: url)
        #expect(try reopened.documents() == [record]); #expect(try reopened.cursor() == "1:1:9007199254740993")
    }
    @Test func testFailedSnapshotRollsBackDocumentsAndCursor() throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalStore(url: url)
        let old = ConnectDocument(id: UUID(), collection: "lists", data: ["title": .string("Old")], revision: try Revision("1"), updatedAt: "2026-10-12T00:00:00Z")
        try store.replaceSnapshot([old], cursor: "1:1:1")
        #expect(throws: ConnectError.self) { try store.replaceSnapshot([old, old], cursor: "1:1:2") }
        #expect(try store.documents() == [old]); #expect(try store.cursor() == "1:1:1")
    }
    @Test func testAccountSwitchDoesNotMergeCaches() throws {
        let a = try location(), b = try location()
        defer { try? FileManager.default.removeItem(at: a.deletingLastPathComponent()); try? FileManager.default.removeItem(at: b.deletingLastPathComponent()) }
        let first = try LocalStore(url: a), second = try LocalStore(url: b)
        try first.enqueue(mutation())
        #expect(try first.mutations().count == 1); #expect(try second.mutations().isEmpty)
    }
}
