import SwiftUI
import UrbitConnect
import UniformTypeIdentifiers

struct PairingView: View {
    @Bindable var store: TodoStore
    @State private var showingRecovery = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                Spacer(minLength: 20)
                Image(systemName: "checkmark.square.fill").font(.system(size: 62, weight: .light)).foregroundStyle(Color.connectAccent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    Text("A little less\non your mind.").font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    Text("Simple lists. Stored on your ship.").font(.title3).foregroundStyle(Color.connectSecondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ship address").font(.subheadline.weight(.medium))
                    TextField("https://your-ship.example", text: $store.endpoint).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("ship-url")
                    Text("Use the HTTPS address configured in %connect. You’ll approve access in your ship’s browser.").font(.footnote).foregroundStyle(Color.connectSecondary)
                }
                Button { Task { await store.connect() } } label: {
                    HStack { if store.connecting { ProgressView().tint(Color.connectButtonText) }; Text(store.connecting ? "Waiting for approval…" : "Connect with Urbit").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.up.right") }.padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(Color.connectButtonFill).foregroundStyle(Color.connectButtonText).controlSize(.large).disabled(store.connecting).accessibilityIdentifier("connect-urbit")
                Text("The app connects directly to your ship. Its publisher has no data server in this flow.").font(.footnote).foregroundStyle(Color.connectSecondary)
                if !store.pending.isEmpty { Text("\(store.pending.count) unsent changes remain on this iPhone. Reconnect to review them.").font(.footnote).foregroundStyle(Color.connectWarning) }
                if !store.retained.isEmpty { Button("Review retained drafts") { showingRecovery = true }.accessibilityIdentifier("retained-drafts") }
                Spacer(minLength: 20)
            }.padding(28).frame(maxWidth: 560)
        }.navigationTitle("Connect Todo").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Use this ship address?", isPresented: Binding(get: { store.proposedOrigin != nil }, set: { if !$0 { store.proposedOrigin = nil } }), titleVisibility: .visible) {
            Button("Use ship address") { if let origin = store.proposedOrigin { store.proposedOrigin = nil; store.endpoint = origin.absoluteString; Task { await store.connect() } } }
            Button("Cancel", role: .cancel) { store.proposedOrigin = nil }
        } message: { Text(store.proposedOrigin?.absoluteString ?? "") }
        .sheet(isPresented: $showingRecovery) { DraftRecoveryView(store: store) }
    }
}

private struct DraftFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}
struct DraftRecoveryView: View {
    @Bindable var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Data?
    @State private var exporting = false
    @State private var discarding: RetainedAccount?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("These changes are stored only in this app. Export before removing an older account. Reconnecting never sends an older account’s drafts automatically.").font(.footnote) }
                ForEach(store.retained) { archive in
                    Section {
                        Text(archive.account?.ship ?? "Previous connection").font(.headline)
                        if let account = archive.account { Text(account.issuer.absoluteString).font(.caption.monospaced()) }
                        Text("\(archive.pendingCount) pending changes" + (archive.isSelected ? " · current account" : ""))
                        Button("Read and export drafts") { Task { preview = await store.exportDrafts(archive) } }
                        if !archive.isSelected { Button(role: .destructive) { discarding = archive } label: { Text("Remove older account…").foregroundStyle(Color.connectAccent) } }
                    }
                }
                if let preview {
                    Section("Draft export") {
                        Text(String(decoding: preview, as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Export JSON") { exporting = true }
                    }
                }
            }.navigationTitle("Retained drafts").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .fileExporter(isPresented: $exporting, document: DraftFile(bytes: preview ?? Data()), contentType: .json, defaultFilename: "connect-drafts") { result in
            if case .failure = result { store.error = "The draft export could not be written. The original drafts remain in this app." }
        }
        .confirmationDialog("Remove this older account?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), titleVisibility: .visible) {
            if let archive = discarding { Button("Discard account and \(archive.pendingCount) drafts", role: .destructive) { Task { await store.discardOlderAccount(archive); discarding = nil; preview = nil } } }
        } message: { Text("This deletes local data for the selected older account. It cannot be recovered from a ship backup if it was never synchronized. Export first.") }
    }
}
