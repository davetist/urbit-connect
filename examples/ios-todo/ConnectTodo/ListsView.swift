import SwiftUI
import UrbitConnect

struct ListsView: View {
    @Bindable var store: TodoStore
    @State private var newTitle = ""
    @State private var showingNewList = false
    @State private var pending: PendingMutation?
    @State private var confirmingDisconnect = false
    @State private var showingRecovery = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "network").foregroundStyle(Color.connectAccent).accessibilityHidden(true)
                        Text(store.account?.ship ?? "Your ship").fixedSize(horizontal: false, vertical: true)
                    }.font(.subheadline.weight(.medium))
                    if let account = store.account {
                        Text(account.issuer.deletingLastPathComponent().absoluteString)
                            .font(.caption.monospaced()).foregroundStyle(Color.connectSecondary)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ship-origin")
                        if account.isDevelopment {
                            Text("Development ship").font(.caption.weight(.medium)).foregroundStyle(Color.connectWarning)
                        }
                    }
                    Text(store.statusTitle).font(.footnote).foregroundStyle(statusColor).accessibilityIdentifier("save-status")
                    if let message = store.state?.message { Text(message).font(.footnote).foregroundStyle(Color.connectSecondary) }
                    if store.state?.connection == .needsAuthorization || store.state?.connection == .revoked {
                        Button("Reconnect with Urbit") { Task { await store.connect() } }.disabled(store.connecting)
                    }
                }.padding(.vertical, 5)
            }
            if !store.attention.isEmpty {
                Section {
                    ForEach(store.attention) { change in
                        Button { pending = change } label: {
                            Label(change.draft?["title"]?.stringValue ?? "Pending deletion", systemImage: "exclamationmark.circle").foregroundStyle(Color.connectWarning)
                        }.accessibilityIdentifier("review-change")
                    }
                } header: { Text("Review changes").foregroundStyle(Color.connectSecondary) }
            }
            Section {
                if store.lists.isEmpty {
                    ContentUnavailableView("Make room for a list", systemImage: "checklist", description: Text(store.state?.hydrated == true ? "Start with Personal, or anything you want to remember." : "Your lists will appear when the ship responds."))
                        .listRowBackground(Color.clear)
                }
                ForEach(store.lists) { row in
                    NavigationLink(value: row.id) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(row.title).font(.headline)
                            if let model = row.model {
                                Text("\(model.tasks.filter(\.completed).count) of \(model.tasks.count) complete").font(.subheadline).foregroundStyle(Color.connectSecondary)
                            } else { Text("Preserved on your ship. Open Connect to inspect it.").font(.caption).foregroundStyle(Color.connectWarning) }
                            if row.pending != nil { Text("Pending changes").font(.caption2).foregroundStyle(Color.connectSecondary) }
                        }.padding(.vertical, 6)
                    }
                }
            } header: { Text("Your lists").foregroundStyle(Color.connectSecondary) }
        }
        .navigationTitle("My lists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("New list", systemImage: "plus") { showingNewList = true }.disabled(!store.canEdit).accessibilityIdentifier("new-list") }
            ToolbarItem(placement: .topBarLeading) { Menu {
                if let account = store.account { Link("Open %connect", destination: account.issuer.deletingLastPathComponent().appending(path: "apps/connect/")) }
                Button("Disconnect", role: .destructive) { confirmingDisconnect = true }
                Button("Review retained drafts") { showingRecovery = true }
            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Connection options") } }
        }
        .alert("New list", isPresented: $showingNewList) {
            TextField("List name", text: $newTitle)
            Button("Create") { Task { if await store.addList(newTitle) != nil { newTitle = "" } } }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Disconnect this iPhone?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await store.disconnect() } }
        } message: { Text("Your ship keeps its documents. Unsent changes remain on this iPhone for recovery.") }
        .sheet(item: $pending) { ConflictView(store: store, item: $0) }
        .sheet(isPresented: $showingRecovery) { DraftRecoveryView(store: store) }
    }
    private var statusColor: Color { store.state?.connection == .online && store.pending.isEmpty ? Color.connectAccent : Color.connectSecondary }
}
