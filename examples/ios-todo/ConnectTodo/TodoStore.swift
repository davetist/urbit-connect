import Foundation
import Observation
import UIKit
import UrbitConnect

struct VisibleList: Identifiable {
    let id: UUID
    let data: JSONObject
    let revision: Revision?
    let pending: PendingMutation?
    var model: TodoList? { try? TodoList(document: data) }
    var title: String { model?.title ?? "Unsupported data" }
}

@MainActor @Observable final class TodoStore {
    private let client: ConnectClient
    @ObservationIgnored private var observation: Task<Void, Never>?
    private var started = false
    var account: ConnectAccount?
    var state: CollectionState?
    var error: String?
    var connecting = false
    var endpoint = ""
    var proposedOrigin: URL?
    var retained: [RetainedAccount] = []
    init() throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appending(path: "UrbitConnect")
        let configuration = try ConnectConfiguration(clientID: "connect-todo-prototype", redirectURI: URL(string: "org.example.urbitconnect.todo:/oauth/callback")!)
        client = try ConnectClient(configuration: configuration, persistenceDirectory: directory)
    }
    deinit { observation?.cancel() }
    func start() async {
        guard !started else { return }; started = true
        do { account = try await client.resume(); endpoint = account?.issuer.deletingLastPathComponent().absoluteString ?? "" }
        catch { self.error = explain(error) }
        await refreshRetained()
        let client = client
        observation = Task { [weak self] in
            let stream = await client.observe(collection: "lists")
            for await state in stream { guard let self else { break }; self.state = state }
        }
    }
    func foreground(_ active: Bool) async { await client.setForeground(active); if active { await refreshRetained() } }
    var canEdit: Bool {
        account != nil && !connecting && state?.connection != .revoked && state?.connection != .needsAuthorization && state?.connection != .disconnected
    }
    var pending: [PendingMutation] { state?.pending ?? [] }
    var attention: [PendingMutation] { pending.filter { $0.status == .conflict || $0.status == .needsAttention } }
    var lists: [VisibleList] {
        var result = Dictionary(uniqueKeysWithValues: (state?.documents ?? []).map { ($0.id, VisibleList(id: $0.id, data: $0.data, revision: $0.revision, pending: nil)) })
        for change in pending {
            if let draft = change.draft { result[change.documentID] = .init(id: change.documentID, data: draft, revision: result[change.documentID]?.revision, pending: change) }
            else if change.status == .pending || change.status == .sending { result.removeValue(forKey: change.documentID) }
        }
        return result.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func list(_ id: UUID) -> VisibleList? { lists.first { $0.id == id } }
    var statusTitle: String {
        if connecting { return "Waiting for your ship" }
        switch state?.connection {
        case .revoked: return "Access revoked"
        case .needsAuthorization: return "Reconnect to continue"
        case .offline: return pending.isEmpty ? "Offline · showing saved data" : "Offline · edits saved on this iPhone"
        case .connecting: return "Connecting…"
        case .online:
            if !attention.isEmpty { return "Changes need your attention" }
            if !pending.isEmpty { return "Saving to your ship…" }
            return state?.hydrated == true ? "Saved on your ship" : "Loading your lists…"
        default: return "Connect to your ship"
        }
    }
    func connect() async {
        guard !connecting else { return }; error = nil
        let address: ConnectEndpoint
        do { address = try ConnectEndpoint(endpoint) } catch { self.error = explain(error); return }
        if address.requiresConfirmation { proposedOrigin = address.origin; return }
        let origin = address.origin
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { error = "The authentication window is unavailable."; return }
        connecting = true; defer { connecting = false }
        do { account = try await client.connect(to: origin, presentation: SystemAuthorizationPresenter(anchor: window)); endpoint = origin.absoluteString; await refreshRetained() }
        catch is CancellationError { }
        catch { self.error = explain(error) }
    }
    func refreshRetained() async { do { retained = try await client.retainedAccounts() } catch { self.error = explain(error) } }
    func exportDrafts(_ archive: RetainedAccount) async -> Data? { do { return try await client.exportDrafts(archiveID: archive.id) } catch { self.error = explain(error); return nil } }
    func discardOlderAccount(_ archive: RetainedAccount) async {
        do { try await client.removeRetainedAccount(archiveID: archive.id, confirmation: archive.id); await refreshRetained() }
        catch { self.error = explain(error) }
    }
    func addList(_ title: String) async -> UUID? {
        error = nil
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else { error = "Use a list name between 1 and 200 characters."; return nil }
        let id = UUID()
        do { _ = try await client.put(collection: "lists", id: id, data: TodoList(title: title).document, expectedRevision: nil); return id }
        catch { self.error = explain(error); return nil }
    }
    func updateList(_ id: UUID, change: (inout TodoList) -> Void) async {
        error = nil
        guard let row = list(id), var model = row.model else { error = "This document uses unsupported data. Inspect it in Connect on your ship."; return }
        change(&model)
        do { _ = try TodoList(document: model.document); _ = try await client.put(collection: "lists", id: id, data: model.document, expectedRevision: row.revision) }
        catch { self.error = explain(error) }
    }
    func addTask(_ title: String, to list: UUID) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500 else { error = "Use a task title between 1 and 500 characters."; return false }
        error = nil; await updateList(list) { $0.tasks.append(.init(id: UUID(), title: title, completed: false)) }; return error == nil
    }
    func deleteList(_ id: UUID) async {
        error = nil
        guard let row = list(id), let revision = row.revision else { error = "Wait for this new list to save before deleting it."; return }
        do { _ = try await client.delete(collection: "lists", id: id, expectedRevision: revision) }
        catch { self.error = explain(error) }
    }
    func resolve(_ item: PendingMutation, with action: ConflictResolution) async {
        do { _ = try await client.resolveConflict(item.id, resolution: action) }
        catch { self.error = explain(error) }
    }
    func disconnect() async {
        do { try await client.disconnect() }
        catch is CancellationError { return }
        catch {
            if await client.account() != nil { self.error = "This iPhone could not clear its saved connection. Try disconnecting again."; return }
            self.error = "Disconnected on this iPhone. The ship could not confirm revocation; revoke the session in Connect when reachable."
        }
        account = nil
        await refreshRetained()
    }
    private func explain(_ error: any Error) -> String {
        switch error {
        case ConnectError.authorizationDenied: return "You denied the connection. No app access was granted."
        case ConnectError.authorizationCancelled: return "Connection cancelled. You can try again when ready."
        case ConnectError.invalidOrigin: return "Use the exact HTTPS origin configured in Connect on your ship."
        case ConnectError.notConnected: return "Connect to your ship before changing data."
        case ConnectError.protocolMismatch: return "This ship is not configured for a compatible version of Connect."
        case ConnectError.missingDesk: return "Connect is not installed at this address. Install the desk on your ship, then try again."
        case ConnectError.notConfigured: return "Open Connect on your ship and set its HTTPS address before pairing."
        case ConnectError.unsupportedProtocol: return "This ship uses an unsupported Connect protocol. Use the compatible desk and SDK versions listed in the integration guide."
        case ConnectError.accountChanged: return "This address now identifies a different ship instance. Review your retained drafts before pairing it."
        case ConnectError.restoreDetected: return "The ship was restored. Reconnect and review your drafts before saving them again."
        case ConnectError.localCapacity(let resource, _):
            switch resource {
            case .pendingMutations: return "This iPhone has 1,000 pending changes. Your new input is kept. Synchronize or review existing drafts before adding another."
            case .pendingRequestBytes: return "Pending changes have reached 16 MiB on this iPhone. Your new input is kept. Synchronize or review existing drafts first."
            case .retainedAccounts: return "This app has 16 saved ship accounts. Export drafts and remove an older account before pairing another."
            }
        case ConnectError.invalidJSON(let message) where message.contains("byte limit"): return "This list exceeds the 16 KiB document limit. Your input is kept. Use another list for additional tasks."
        case ConnectError.invalidJSON(let message), ConnectError.storage(let message), ConnectError.transport(let message): return message
        case ConnectError.server(_, _, let message): return message
        case TodoModelError.unsupportedSchema, TodoModelError.invalidData, TodoModelError.duplicateTaskID: return "This change does not match the supported todo format. Your existing data is unchanged."
        case let network as URLError:
            switch network.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .secureConnectionFailed: return "The ship’s HTTPS certificate could not be verified. Correct its certificate before connecting."
            case .cannotFindHost, .dnsLookupFailed: return "The ship address could not be found. Check its hostname and your network connection."
            default: return "The ship could not be reached. Your existing data and drafts remain on this iPhone."
            }
        default: return "The connection could not finish. Your existing data and drafts remain on this iPhone."
        }
    }
}
