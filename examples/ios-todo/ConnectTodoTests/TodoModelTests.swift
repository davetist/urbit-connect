import Foundation
import Testing
@testable import ConnectTodo
import UrbitConnect

struct TodoModelTests {
    @Test func testTodoRoundTrip() throws {
        let value = TodoList(title: "Personal", tasks: [.init(id: UUID(), title: "Buy milk", completed: false)])
        #expect(try TodoList(document: value.document) == value)
    }
    @Test func testUnsupportedTodoSchemaRemainsVisibleAsUnsupported() throws {
        let document: JSONObject = ["schemaVersion": .number("2"), "title": .string("Future data"), "tasks": .array([])]
        #expect(throws: TodoModelError.self) { try TodoList(document: document) }
        #expect(document["title"] == .string("Future data"))
    }
    @Test func testDuplicateTaskIDsRejected() throws {
        let id = UUID(), value = TodoList(title: "Personal", tasks: [.init(id: id, title: "One", completed: false), .init(id: id, title: "Two", completed: true)])
        #expect(throws: TodoModelError.self) { try TodoList(document: value.document) }
    }
    @Test func testUnknownFieldsAreNotSilentlyDiscarded() {
        var value = TodoList(title: "Personal").document; value["ownerNote"] = .string("Keep this")
        #expect(throws: TodoModelError.self) { try TodoList(document: value) }
    }
}
