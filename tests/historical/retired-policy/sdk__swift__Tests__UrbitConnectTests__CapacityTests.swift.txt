import CSQLite
import Foundation
import Testing
@testable import UrbitConnect

struct CapacityTests {
    func url() -> URL { FileManager.default.temporaryDirectory.appending(path: "connect-capacity-" + UUID().uuidString).appending(path: "cache.sqlite") }
    func mutation(id: UUID = UUID(), bytes: Int? = nil) throws -> StoredMutation {
        var value = StoredMutation(id: .init(rawValue: id), collection: "notes", documentID: UUID(), draft: ["text": .string("Queued")], expected: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000), status: .pending)
        if let bytes {
            // A valid JSON request of exact size; LocalStore preserves opaque request bytes.
            value.body = Data(("{\"padding\":\"" + String(repeating: "x", count: bytes - 14) + "\"}").utf8)
            #expect(value.body?.count == bytes)
        } else { value.body = try value.requestBody() }
        return value
    }
    @Test func outboxCountLimitRejectsOnlyTheNewMutationAndReleasesAfterRemoval() throws {
        let location = url(); defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try LocalStore(url: location)
        for _ in 0..<1000 { try store.enqueue(mutation()) }
        let before = try store.mutations()
        #expect(throws: ConnectError.self) { try store.enqueue(mutation()) }
        let after = try store.mutations()
        #expect(after.count == before.count)
        let preserved = Array(after.prefix(before.count)) == before
        #expect(preserved)
        try store.removeMutation(before[0].id)
        try store.enqueue(mutation())
        #expect(try LocalStore(url: location).mutations().count == 1000)
    }
    @Test func encodedRequestByteLimitAcceptsExactBoundaryAndPreservesDrafts() throws {
        let location = url(); defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try LocalStore(url: location)
        for _ in 0..<128 { try store.enqueue(mutation(bytes: 131072)) }
        let before = try store.mutations()
        #expect(throws: ConnectError.self) { try store.enqueue(mutation(bytes: 14)) }
        let after = try store.mutations()
        #expect(after.count == before.count)
        let preserved = Array(after.prefix(before.count)) == before
        #expect(preserved)
        try store.removeMutation(before[0].id)
        try store.enqueue(mutation(bytes: 131072))
        #expect(try LocalStore(url: location).mutations().count == 128)
    }
    @Test func equalClocksPreserveEnqueueOrderRatherThanUUIDOrder() throws {
        let location = url(); defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
        let store = try LocalStore(url: location)
        let first = try mutation(id: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!), next = try mutation(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        try store.enqueue(first); try store.enqueue(next)
        #expect(try LocalStore(url: location).mutations().map(\.id) == [first.id, next.id])
    }
}
