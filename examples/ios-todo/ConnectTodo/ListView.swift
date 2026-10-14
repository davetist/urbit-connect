import SwiftUI
import UrbitConnect

struct TodoListView: View {
    @Bindable var store: TodoStore
    let id: UUID
    @State private var taskTitle = ""
    @State private var rename = ""
    @State private var renaming = false
    @State private var editingTask: TodoTask?
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let row = store.list(id), let model = row.model {
                List {
                    Section {
                        Text(store.statusTitle).font(.footnote).foregroundStyle(Color.connectSecondary).accessibilityIdentifier("save-status")
                        if let message = store.state?.message { Text(message).font(.footnote).foregroundStyle(Color.connectSecondary).accessibilityIdentifier("sync-message") }
                    }
                    Section {
                        HStack {
                            TextField("Add a task", text: $taskTitle, axis: .vertical).submitLabel(.done).onSubmit { addTask() }.accessibilityIdentifier("task-title")
                            Button("Add", systemImage: "plus.circle.fill") { addTask() }.labelStyle(.iconOnly).font(.title2).disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit).accessibilityIdentifier("add-task")
                        }
                    }
                    Section {
                        ForEach(model.tasks) { task in
                            HStack(alignment: .top, spacing: 13) {
                                Button { Task { await store.updateList(id) { value in if let index = value.tasks.firstIndex(where: { $0.id == task.id }) { value.tasks[index].completed.toggle() } } } } label: {
                                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(task.completed ? Color.connectAccent : Color.connectSecondary)
                                }.buttonStyle(.borderless).disabled(!store.canEdit).accessibilityLabel(task.completed ? "Mark \(task.title) incomplete" : "Complete \(task.title)")
                                Text(task.title).strikethrough(task.completed).foregroundStyle(task.completed ? Color.connectSecondary : .primary).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 5)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { Task { await store.updateList(id) { $0.tasks.removeAll { $0.id == task.id } } } }.disabled(!store.canEdit)
                                Button("Edit") { editingTask = task }.tint(Color(white: 0.34)).disabled(!store.canEdit)
                            }
                            .contextMenu { Button("Edit task") { editingTask = task }.disabled(!store.canEdit) }
                        }
                        if model.tasks.isEmpty { Text("Nothing to remember yet.").foregroundStyle(Color.connectSecondary).padding(.vertical, 8) }
                    } header: { Text("\(model.tasks.filter { !$0.completed }.count) remaining").foregroundStyle(Color.connectSecondary) }
                }
                .navigationTitle(model.title)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu {
                    Button("Rename list") { if rename.isEmpty { rename = model.title }; renaming = true }.disabled(!store.canEdit)
                    Button("Delete list", role: .destructive) { deleting = true }.disabled(!store.canEdit || row.revision == nil)
                } label: { Image(systemName: "ellipsis").accessibilityLabel("List options") } } }
            } else if let row = store.list(id) {
                ScrollView { VStack(alignment: .leading, spacing: 18) {
                    Label("Unsupported data", systemImage: "doc.badge.ellipsis").font(.title2)
                    Text("This document does not match the todo format this app understands. It stays intact on your ship and cannot be edited here.")
                    if let data = try? JSONValue.object(row.data).encoded(), let text = String(data: data, encoding: .utf8) { Text(text).font(.caption.monospaced()).textSelection(.enabled) }
                }.padding() }.navigationTitle("Document")
            } else { ContentUnavailableView("List unavailable", systemImage: "tray", description: Text("It may have been deleted or access may have changed.")) }
        }
        .alert("Rename list", isPresented: $renaming) {
            TextField("List name", text: $rename)
            Button("Save") { Task { await store.updateList(id) { $0.title = rename.trimmingCharacters(in: .whitespacesAndNewlines) }; if store.error == nil { rename = "" } } }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this list and its tasks?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) { Task { await store.deleteList(id); if store.error == nil { dismiss() } } }
        }
        .sheet(item: $editingTask) { task in EditTaskView(store: store, listID: id, task: task) }
    }
    private func addTask() { let title = taskTitle; Task { if await store.addTask(title, to: id), taskTitle == title { taskTitle = "" } } }
}

private struct EditTaskView: View {
    let store: TodoStore
    let listID: UUID
    let task: TodoTask
    @State private var title: String
    @Environment(\.dismiss) private var dismiss
    init(store: TodoStore, listID: UUID, task: TodoTask) { self.store = store; self.listID = listID; self.task = task; _title = State(initialValue: task.title) }
    var body: some View {
        NavigationStack { Form { TextField("Task title", text: $title, axis: .vertical).accessibilityLabel("Task title").accessibilityIdentifier("edit-task-title") }
            .navigationTitle("Edit task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task {
                    await store.updateList(listID) { value in if let index = value.tasks.firstIndex(where: { $0.id == task.id }) { value.tasks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    if store.error == nil { dismiss() }
                } } }
            }
        }.presentationDetents([.medium])
    }
}
