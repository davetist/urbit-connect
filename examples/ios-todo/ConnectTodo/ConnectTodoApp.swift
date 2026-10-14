import SwiftUI

@main struct ConnectTodoApp: App {
    @State private var store: TodoStore?
    @State private var failure: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let store { TodoRoot(store: store) }
                else if let failure { ContentUnavailableView("Unable to prepare Connect", systemImage: "externaldrive.badge.exclamationmark", description: Text(failure)) }
                else { ProgressView("Preparing your lists…").task { do { store = try TodoStore() } catch { failure = error.localizedDescription } } }
            }.tint(Color.connectAccent)
        }
    }
}
private struct TodoRoot: View {
    @Bindable var store: TodoStore
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            Group { if store.account == nil { PairingView(store: store) } else { ListsView(store: store) } }
                .navigationDestination(for: UUID.self) { TodoListView(store: store, id: $0) }
        }
        .task { await store.start() }
        .onChange(of: phase) { _, value in Task { await store.foreground(value != .background) } }
        .alert("Connect Todo", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

// Neutral Urbit-inspired colors retain contrast in both system appearances.
extension Color {
    static let connectSecondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.72, alpha: 1)
            : UIColor(white: 0.34, alpha: 1)
    })
    static let connectAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.95, alpha: 1)
            : UIColor(white: 0.09, alpha: 1)
    })
    static let connectWarning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.84, alpha: 1)
            : UIColor(white: 0.23, alpha: 1)
    })
    static let connectButtonFill = connectAccent
    static let connectButtonText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.09, alpha: 1)
            : UIColor.white
    })
}
