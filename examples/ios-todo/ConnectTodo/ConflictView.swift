import SwiftUI
import UrbitConnect

struct ConflictView: View {
    let store: TodoStore
    let item: PendingMutation
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(item.status == .conflict ? "Two versions need a decision" : "Review your saved draft").font(.title2.weight(.semibold))
                    Text(item.message ?? "Your local changes are preserved. Choose how to continue.").foregroundStyle(Color.connectSecondary)
                }
                Section { Text(summary(displayDraft)).textSelection(.enabled) } header: { Text("Your draft").foregroundStyle(Color.connectSecondary) }
                if let current = item.current { Section { Text(summary(current.data)).textSelection(.enabled) } header: { Text("Current ship version").foregroundStyle(Color.connectSecondary) } }
                Section {
                    Button(role: .destructive) { resolve(.useRemote) } label: { Text("Use ship version").foregroundStyle(Color.connectAccent) }
                    if item.current != nil && store.canEdit { Button("Save my draft over current version") { resolve(.retryWithCurrent) } }
                    if item.draft != nil && store.canEdit { Button("Save as a new list") { resolve(.saveAsNewDocument) } }
                } footer: { Text("Changes are never merged or overwritten automatically.").foregroundStyle(Color.connectSecondary) }
            }.navigationTitle("Review changes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private var displayDraft: JSONObject? { store.pending.last { $0.documentID == item.documentID && $0.collection == item.collection }?.draft ?? item.draft }
    private func resolve(_ action: ConflictResolution) { Task { await store.resolve(item, with: action); if store.error == nil { dismiss() } } }
    private func summary(_ data: JSONObject?) -> String {
        guard let data else { return "Delete this list" }
        if let model = try? TodoList(document: data) { return model.title + "\n\n" + model.tasks.map { ($0.completed ? "✓ " : "○ ") + $0.title }.joined(separator: "\n") }
        return (try? JSONValue.object(data).encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "Unsupported document"
    }
}
