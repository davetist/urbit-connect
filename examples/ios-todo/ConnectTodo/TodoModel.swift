import Foundation
import UrbitConnect

struct TodoTask: Identifiable, Equatable {
    let id: UUID
    var title: String
    var completed: Bool
}
struct TodoList: Equatable {
    var title: String
    var tasks: [TodoTask]
    init(title: String, tasks: [TodoTask] = []) { self.title = title; self.tasks = tasks }
    init(document: JSONObject) throws {
        guard Set(document.keys) == ["schemaVersion", "title", "tasks"], document["schemaVersion"] == .number("1") else { throw TodoModelError.unsupportedSchema }
        guard let title = document["title"]?.stringValue, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              let rows = document["tasks"]?.arrayValue else { throw TodoModelError.invalidData }
        var tasks: [TodoTask] = [], seen = Set<UUID>()
        for row in rows {
            guard let object = row.objectValue, Set(object.keys) == ["id", "title", "completed"],
                  let raw = object["id"]?.stringValue, ConnectIdentifiers.document(raw), let id = UUID(uuidString: raw),
                  let taskTitle = object["title"]?.stringValue, !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, taskTitle.count <= 500,
                  let completed = object["completed"]?.boolValue else { throw TodoModelError.invalidData }
            guard seen.insert(id).inserted else { throw TodoModelError.duplicateTaskID }
            tasks.append(.init(id: id, title: taskTitle, completed: completed))
        }
        self.title = title; self.tasks = tasks
    }
    var document: JSONObject {
        ["schemaVersion": .number("1"), "title": .string(title), "tasks": .array(tasks.map { .object(["id": .string($0.id.uuidString.lowercased()), "title": .string($0.title), "completed": .bool($0.completed)]) })]
    }
}
enum TodoModelError: Error { case unsupportedSchema, invalidData, duplicateTaskID }
