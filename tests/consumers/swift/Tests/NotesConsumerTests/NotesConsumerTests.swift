import Foundation
import Testing
import NotesConsumer
import UrbitConnect

struct NotesConsumerTests {
    @Test func distinctSchemaRoundTripsWithoutSDKPrivateHooks() throws {
        let document = NotesConsumer.document(text: "A different document schema")
        #expect(try JSONValue.parse(JSONValue.object(document).encoded()).objectValue == document)
        #expect(document["text"] == .string("A different document schema"))
        #expect(document["tasks"] == nil)
    }
    @Test func unpairedPublicConsumerCannotEnqueueAuthority() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "connect-consumer-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let consumer = try NotesConsumer(directory: root)
        #expect(try await consumer.resume() == nil)
        await #expect(throws: ConnectError.notConnected) { try await consumer.save(id: UUID(), text: "Unapproved", revision: nil) }
    }
}
