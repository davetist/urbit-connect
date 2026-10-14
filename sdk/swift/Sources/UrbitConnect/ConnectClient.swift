import Foundation

/// The only coordinator of credentials, confirmed records, outbox and sync tasks.
public actor ConnectClient {
    private let configuration: ConnectConfiguration
    private let directory: URL
    private let tokens: any TokenStore
    private let makeTransport: @Sendable (URL) throws -> any ConnectTransport
    private let clock: @Sendable () -> Date
    private let automaticallySync: Bool
    private var transport: (any ConnectTransport)?
    private var credentials: Credentials?
    private var key: String?
    private var store: LocalStore?
    private var generation = UUID()
    private var foreground = true
    private var status: ConnectionStatus = .disconnected
    private var message: String?
    private var syncTask: Task<Void, Never>?
    private var pollTask: Task<HTTPResponse, any Error>?
    private var refreshTask: Task<Void, any Error>?
    private var observers: [UUID: (String, AsyncStream<CollectionState>.Continuation)] = [:]
    private static let maximumRetainedAccounts = 16

    public init(configuration: ConnectConfiguration, persistenceDirectory: URL) throws {
        self.configuration = configuration; directory = persistenceDirectory
        tokens = KeychainTokenStore(); makeTransport = { try HTTPTransport(origin: $0) }; clock = Date.init
        automaticallySync = true
        try Self.prepare(directory)
    }
    init(configuration: ConnectConfiguration, persistenceDirectory: URL, tokens: any TokenStore,
         transport: @escaping @Sendable (URL) throws -> any ConnectTransport,
         clock: @escaping @Sendable () -> Date = Date.init, automaticallySync: Bool = true) throws {
        self.configuration = configuration; directory = persistenceDirectory; self.tokens = tokens
        makeTransport = transport; self.clock = clock; self.automaticallySync = automaticallySync
        try Self.prepare(directory)
    }
    private static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var location = directory; try location.setResourceValues(resource)
    }
    private var selectedURL: URL { directory.appending(path: "selected-" + Data(configuration.clientID.utf8).sha256Hex + ".txt") }
    private func check(_ expected: UUID) throws {
        try Task.checkCancellation(); guard generation == expected else { throw CancellationError() }
    }
    private func stopTasks() {
        syncTask?.cancel(); syncTask = nil; pollTask?.cancel(); pollTask = nil; refreshTask?.cancel(); refreshTask = nil
        generation = UUID()
    }
    public func account() -> ConnectAccount? { credentials?.account }
    public func connectionStatus() -> ConnectionStatus { status }

    /// Checks the endpoint without opening consent or changing a saved pairing.
    public func preflight(origin: URL, expected: ConnectAccount? = nil) async throws -> ConnectAccount {
        let origin = try HTTPTransport.validateOrigin(origin)
        return try await inspect(try makeTransport(origin), origin: origin, expected: expected)
    }
    private func inspect(_ candidate: any ConnectTransport, origin: URL, expected: ConnectAccount? = nil) async throws -> ConnectAccount {
        let response = try await candidate.send(path: "/connect/v1/info", method: "GET", body: nil, token: nil, form: false)
        if response.status == 404 { throw ConnectError.missingDesk }
        guard response.status == 200 else { throw try ServerFailure(response) }
        let wire = try response.json
        guard case .number = wire["protocolVersion"] else { throw ConnectError.protocolMismatch }
        guard wire["protocolVersion"] == .number("1") else { throw ConnectError.unsupportedProtocol }
        if wire["configured"] == .bool(false) { throw ConnectError.notConfigured }
        return try SyncCodec.info(wire, origin: origin, expected: expected)
    }

    public func connect(to origin: URL, presentation: any AuthorizationPresenter) async throws -> ConnectAccount {
        let origin = try HTTPTransport.validateOrigin(origin)
        stopTasks(); let expected = generation; status = .connecting; message = nil; publish()
        do {
            let candidate = try makeTransport(origin)
            let account = try await inspect(candidate, origin: origin)
            try check(expected)
            try checkAccountCapacity(account)
            let request = try AuthorizationRequest(configuration: configuration, origin: origin)
            let callback = try await presentation.authorize(url: request.url, callbackScheme: configuration.redirectURI.scheme!)
            try check(expected); let code = try request.code(from: callback)
            let body = HTTPTransport.form(["grant_type": "authorization_code", "client_id": configuration.clientID, "redirect_uri": configuration.redirectURI.absoluteString, "code": code, "code_verifier": request.verifier])
            let response = try await candidate.send(path: "/connect/oauth/token", method: "POST", body: body, token: nil, form: true)
            try check(expected); guard response.status == 200 else { throw try ServerFailure(response) }
            let next = try decodeCredentials(response.json, account: account)
            let identity = try await candidate.send(path: "/connect/v1/identity", method: "GET", body: nil, token: next.access, form: false)
            try check(expected); guard identity.status == 200 else { throw try ServerFailure(identity) }
            try verifyIdentity(identity.json, credentials: next)
            try install(next, transport: candidate)
            status = .online; publish(); startSynchronization(); return account
        } catch {
            if generation == expected {
                status = credentials == nil ? .disconnected : .offline
                message = userMessage(error); publish(); startSynchronization()
            }
            throw error
        }
    }
    public func resume() async throws -> ConnectAccount? {
        stopTasks()
        credentials = nil; transport = nil; key = nil; store = nil; status = .disconnected; message = nil
        guard FileManager.default.fileExists(atPath: selectedURL.path) else { publish(); return nil }
        let selected = try String(contentsOf: selectedURL, encoding: .utf8)
        guard selected.count == 64, selected.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ConnectError.storage("Invalid selected account") }
        key = selected; store = try LocalStore(url: directory.appending(path: selected + ".sqlite"))
        guard let data = try tokens.read(key: selected) else {
            try suspend(.needsAuthorization, reason: "This device’s credentials are unavailable. Connect again to recover unsent drafts.", removeCredentials: false)
            return nil
        }
        let restored = try Credentials.decode(data)
        guard restored.grant.clientId == configuration.clientID, Self.accountKey(restored.account, client: configuration.clientID) == selected else { throw ConnectError.accountChanged }
        try recordRecoveryAccount(restored.account, in: store!)
        credentials = restored
        let origin = try HTTPTransport.validateOrigin(restored.account.issuer.deletingLastPathComponent())
        transport = try makeTransport(origin)
        if restored.refreshInFlight {
            try suspend(.needsAuthorization, reason: "The last credential refresh was interrupted. Connect again before syncing.", removeCredentials: false)
            return restored.account
        }
        status = .offline; message = nil; publish(); startSynchronization(); return restored.account
    }
    private static func accountKey(_ account: ConnectAccount, client: String) -> String {
        Data((account.issuer.absoluteString + "\0" + account.instanceId + "\0" + client).utf8).sha256Hex
    }
    private func install(_ next: Credentials, transport: any ConnectTransport) throws {
        try checkAccountCapacity(next.account)
        let selected = Self.accountKey(next.account, client: configuration.clientID)
        let storage = try LocalStore(url: directory.appending(path: selected + ".sqlite"))
        if let old = try storage.metadata("binding"), let binding = try JSONValue.parse(old).objectValue {
            let changed = binding["epoch"]?.stringValue != next.account.syncEpoch.rawValue || binding["namespaceEpoch"]?.stringValue != next.grant.namespaceEpoch.rawValue || binding["namespace"]?.stringValue != next.grant.namespace
            if changed {
                for var pending in try storage.mutations() { pending.status = .needsAttention; pending.message = "This app space or restore epoch changed. Review this draft before saving it again."; pending.current = nil; try storage.update(pending) }
                try storage.clearConfirmed()
            }
        }
        if !next.grant.scopes.contains("documents:read") { try storage.clearConfirmed() }
        try storage.setMetadata("binding", value: JSONValue.object(["epoch": .string(next.account.syncEpoch.rawValue), "namespaceEpoch": .string(next.grant.namespaceEpoch.rawValue), "namespace": .string(next.grant.namespace)]).encoded())
        try recordRecoveryAccount(next.account, in: storage)
        try tokens.write(next.encoded(), key: selected)
        try Data(selected.utf8).write(to: selectedURL, options: .atomic)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: selectedURL.path)
        stopTasks()
        credentials = next; key = selected; store = storage; self.transport = transport
    }
    private func decodeCredentials(_ wire: JSONObject, account: ConnectAccount) throws -> Credentials {
        let grant = try ConnectGrant(wire: wire.object("grant"))
        guard grant.clientId == configuration.clientID, Set(grant.scopes) == Set(configuration.requestedScopes),
              wire["token_type"]?.stringValue == "Bearer", case .number(let raw) = wire["expires_in"],
              let seconds = Double(raw), seconds > 0, seconds <= 600 else { throw ConnectError.protocolMismatch }
        return try .init(account: account, grant: grant, access: wire.string("access_token"), refresh: wire.string("refresh_token"), accessExpires: clock().addingTimeInterval(seconds), refreshInFlight: false)
    }
    private func verifyIdentity(_ wire: JSONObject, credentials expected: Credentials) throws {
        let account = try ConnectAccount(wire: wire.object("account")), grant = try ConnectGrant(wire: wire.object("grant"))
        guard account.issuer == expected.account.issuer, account.instanceId == expected.account.instanceId else { throw ConnectError.accountChanged }
        guard account.syncEpoch == expected.account.syncEpoch else { throw ConnectError.restoreDetected }
        guard grant == expected.grant else { throw ConnectError.unauthorized }
    }
    public func get(collection: String, id: UUID) async throws -> ConnectDocument? {
        try await documents(in: collection).first { $0.id == id }
    }
    public func documents(in collection: String) async throws -> [ConnectDocument] {
        guard ConnectIdentifiers.collection(collection) else { throw ConnectError.invalidIdentifier }
        return try store?.documents().filter { $0.collection == collection } ?? []
    }
    public func put(collection: String, id: UUID, data: JSONObject, expectedRevision: Revision?) async throws -> PendingMutationID {
        _ = try JSONValue.object(data).encoded(maxBytes: 16_384)
        return try queue(collection: collection, id: id, data: data, expected: expectedRevision)
    }
    public func delete(collection: String, id: UUID, expectedRevision: Revision) async throws -> PendingMutationID {
        try queue(collection: collection, id: id, data: nil, expected: expectedRevision)
    }
    private func queue(collection: String, id: UUID, data: JSONObject?, expected: Revision?) throws -> PendingMutationID {
        guard ConnectIdentifiers.collection(collection) else { throw ConnectError.invalidIdentifier }
        guard let credentials, let store, status == .online || status == .offline else { throw ConnectError.notConnected }
        guard credentials.grant.scopes.contains(data == nil ? "documents:delete" : "documents:write") else { throw ConnectError.server(status: 403, code: "insufficient_scope", message: "This app lacks permission for that operation") }
        let previous = try store.mutations().last { $0.collection == collection && $0.documentID == id }
        var mutation = StoredMutation(id: .init(rawValue: UUID()), collection: collection, documentID: id, draft: data, expected: expected, createdAt: clock(), status: .pending, dependsOn: previous?.id)
        if previous == nil { mutation.body = try mutation.requestBody() }
        try store.enqueue(mutation); publish(); pollTask?.cancel(); startSynchronization(); return mutation.id
    }
    public func observe(collection: String) async -> AsyncStream<CollectionState> {
        let id = UUID(), pair = AsyncStream<CollectionState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = (collection, pair.continuation)
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        publish(); return pair.stream
    }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func publish() {
        do {
            let docs = try store?.documents() ?? [], pending = try store?.mutations() ?? [], hydrated = try store?.isHydrated() ?? false
            for (collection, stream) in observers.values { stream.yield(.init(documents: docs.filter { $0.collection == collection }, pending: pending.filter { $0.collection == collection }.map(\.publicValue), hydrated: hydrated, connection: status, message: message)) }
        } catch {
            for (_, stream) in observers.values { stream.yield(.init(documents: [], pending: [], hydrated: false, connection: .offline, message: userMessage(error))) }
        }
    }
    public func recoveryDrafts() throws -> [PendingMutation] { try store?.mutations().map(\.publicValue) ?? [] }
    private static func validArchiveID(_ id: String) -> Bool {
        id.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func accountFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]).filter {
            guard $0.pathExtension == "sqlite", Self.validArchiveID($0.deletingPathExtension().lastPathComponent) else { return false }
            guard try $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ConnectError.storage("A saved account path is invalid") }
            return true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func checkAccountCapacity(_ account: ConnectAccount) throws {
        let id = Self.accountKey(account, client: configuration.clientID)
        let files = try accountFiles()
        guard files.contains(where: { $0.deletingPathExtension().lastPathComponent == id }) || files.count < Self.maximumRetainedAccounts else {
            throw ConnectError.localCapacity(resource: .retainedAccounts, limit: Self.maximumRetainedAccounts)
        }
    }
    private func recordRecoveryAccount(_ account: ConnectAccount, in storage: LocalStore) throws {
        try storage.setMetadata("recovery-account", value: JSONValue.object(["clientId": .string(configuration.clientID), "account": .object(account.wire)]).encoded())
    }
    /// Lists local accounts, including drafts whose credentials have been revoked.
    public func retainedAccounts() throws -> [RetainedAccount] {
        try accountFiles().compactMap { file in
            let id = file.deletingPathExtension().lastPathComponent, storage = try LocalStore(url: file)
            var account: ConnectAccount?
            if let data = try storage.metadata("recovery-account") {
                guard let wire = try JSONValue.parse(data).objectValue else { throw ConnectError.storage("Invalid saved account metadata") }
                guard wire["clientId"]?.stringValue == configuration.clientID else { return nil }
                account = try ConnectAccount(wire: wire.object("account"))
            } else if let data = try tokens.read(key: id) {
                let saved = try Credentials.decode(data)
                guard saved.grant.clientId == configuration.clientID, Self.accountKey(saved.account, client: configuration.clientID) == id else { return nil }
                account = saved.account
            }
            return .init(id: id, account: account, pendingCount: try storage.mutations().count, isSelected: id == key)
        }
    }
    /// User-requested data export. Contains draft bodies; contains no credentials.
    public func exportDrafts(archiveID: String) throws -> Data {
        guard Self.validArchiveID(archiveID), let archive = try retainedAccounts().first(where: { $0.id == archiveID }) else { throw ConnectError.invalidIdentifier }
        let saved = try LocalStore(url: directory.appending(path: archiveID + ".sqlite"))
        let drafts = try saved.mutations().map { mutation -> JSONValue in
            .object(["mutationId": .string(mutation.id.rawValue.uuidString.lowercased()), "collection": .string(mutation.collection), "documentId": .string(mutation.documentID.uuidString.lowercased()), "draft": mutation.draft.map(JSONValue.object) ?? .null, "expectedRevision": mutation.expected.map { .string($0.rawValue) } ?? .null, "status": .string(mutation.status.rawValue)])
        }
        return try JSONValue.object(["formatVersion": .number("1"), "clientId": .string(configuration.clientID), "account": archive.account.map { .object($0.wire) } ?? .null, "drafts": .array(drafts)]).encoded(maxBytes: 32 * 1024 * 1024, maxDepth: 24)
    }
    /// Deliberately discards an older account after the caller confirms its ID.
    public func removeRetainedAccount(archiveID: String, confirmation: String) throws {
        guard archiveID == confirmation, Self.validArchiveID(archiveID), archiveID != key,
              try retainedAccounts().contains(where: { $0.id == archiveID }) else { throw ConnectError.invalidIdentifier }
        try tokens.delete(key: archiveID)
        for suffix in [".sqlite", ".sqlite-wal", ".sqlite-shm"] {
            let file = directory.appending(path: archiveID + suffix)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
    public func setForeground(_ active: Bool) async {
        foreground = active
        if !active && status == .connecting { return }
        if active { startSynchronization() }
        else { stopTasks() }
    }
    private func startSynchronization() {
        guard automaticallySync, foreground, syncTask == nil, credentials != nil, status == .online || status == .offline else { return }
        let expected = generation
        syncTask = Task { [weak self] in await self?.runLoop(expected) }
    }
    private func runLoop(_ expected: UUID) async {
        var backoff: UInt64 = 1
        while !Task.isCancelled && generation == expected && foreground {
            do {
                try await syncOnce(); try check(expected); backoff = 1
                guard credentials != nil, status != .revoked, status != .needsAuthorization else { break }
                if try store?.mutations().contains(where: { $0.dependsOn == nil && $0.acknowledged == nil && ($0.status == .pending || $0.status == .sending) }) == true { continue }
                if credentials!.grant.scopes.contains("documents:read"), let cursor = try store?.cursor() {
                    let path = "/connect/v1/changes?after=" + Self.query(cursor) + "&wait=25&limit=100"
                    let poll = Task { try await self.authorized(path: path, generation: expected) }
                    pollTask = poll
                    do {
                        let response = try await poll.value; try check(expected); pollTask = nil
                        try await consumeChanges(response, generation: expected)
                    } catch {
                        let signaled = poll.isCancelled && !Task.isCancelled && generation == expected
                        if generation == expected { pollTask = nil }
                        if signaled { continue }; throw error
                    }
                } else { try await Task.sleep(for: .seconds(1)) }
            } catch {
                if Task.isCancelled || generation != expected { break }
                if status == .revoked || status == .needsAuthorization { break }
                if case ConnectError.protocolMismatch = error {
                    try? suspend(.needsAuthorization, reason: userMessage(error), removeCredentials: true); break
                }
                if case ConnectError.invalidJSON = error {
                    try? suspend(.needsAuthorization, reason: "The ship returned invalid protocol data. Review the connection before retrying.", removeCredentials: true); break
                }
                if let failure = error as? ServerFailure, failure.status == 429, failure.code == "poll_capacity", status == .online {
                    // A terminated app's prior poll can survive until its deadline.
                    // Ordinary synchronization just succeeded; retry the watch without
                    // misreporting acknowledged data as an offline connection.
                    message = "Reconnecting live updates…"; publish()
                } else {
                    status = .offline; message = userMessage(error); publish()
                }
                let delay = RetryDelay.seconds(backoff: backoff, retryAfter: (error as? ServerFailure)?.retryAfter)
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                backoff = min(30, backoff * 2)
            }
        }
        if generation == expected { syncTask = nil }
    }
    func syncOnce() async throws {
        guard let credentials, let transport, let store, status != .revoked, status != .needsAuthorization else { throw ConnectError.notConnected }
        let expected = generation
        let origin = try HTTPTransport.validateOrigin(credentials.account.issuer.deletingLastPathComponent())
        let info = try await transport.send(path: "/connect/v1/info", method: "GET", body: nil, token: nil, form: false)
        try check(expected)
        do { guard info.status == 200 else { throw try ServerFailure(info) }; _ = try SyncCodec.info(info.json, origin: origin, expected: credentials.account) }
        catch let error as ConnectError where error == .accountChanged || error == .restoreDetected || error == .protocolMismatch || error == .invalidOrigin {
            try suspend(.needsAuthorization, reason: userMessage(error), removeCredentials: true); throw error
        }
        if credentials.grant.scopes.contains("documents:read"), try !store.isHydrated() { try await takeSnapshot(generation: expected) }
        try await flushOutbox(generation: expected)
        if self.credentials?.grant.scopes.contains("documents:read") == true { try await pullChanges(generation: expected) }
        for pending in try store.mutations() where pending.acknowledged != nil && pending.status != .needsAttention && pending.status != .conflict { try store.completeAcknowledged(pending) }
        status = .online; message = nil; publish()
    }
    private func flushOutbox(generation expected: UUID) async throws {
        guard let store else { throw ConnectError.notConnected }
        let pending = try store.mutations()
        for var mutation in pending where mutation.dependsOn == nil && mutation.acknowledged == nil && (mutation.status == .pending || mutation.status == .sending) {
            try check(expected)
            if clock().timeIntervalSince(mutation.createdAt) >= 30 * 86400 {
                mutation.status = .needsAttention; mutation.message = "This draft is older than the retry receipt window. Review it before saving again."; try store.update(mutation); continue
            }
            if mutation.body == nil { mutation.body = try mutation.requestBody() }
            mutation.status = .sending; try store.update(mutation); publish()
            let response = try await authorized(path: "/connect/v1/mutations", method: "POST", body: mutation.body, generation: expected)
            try check(expected)
            if response.status == 200 {
                mutation.acknowledged = try SyncCodec.commit(response.json, mutation: mutation); try store.update(mutation)
            } else {
                let failure = try ServerFailure(response)
                if failure.status == 409 && failure.code == "conflict" {
                    mutation.status = .conflict; mutation.message = failure.message
                    mutation.current = try failure.detail["current"]?.objectValue.map(ConnectDocument.init(wire:))
                } else if (400..<500).contains(failure.status) && failure.status != 429 {
                    mutation.status = .needsAttention; mutation.message = failure.message
                } else { mutation.status = .pending; try store.update(mutation); throw failure }
                try store.update(mutation); publish()
            }
        }
    }
    private func takeSnapshot(generation expected: UUID) async throws {
        guard let store else { throw ConnectError.notConnected }
        for _ in 0..<3 {
            var response = try await authorized(path: "/connect/v1/snapshots", method: "POST", body: Data("{}".utf8), generation: expected)
            try check(expected); guard response.status == 200 else { throw try ServerFailure(response) }
            var wire = try response.json, rows: [ConnectDocument] = []
            let id = try wire.string("snapshotId"), cursor = try wire.string("atCursor")
            var expired = false, seenPages = Set<String>()
            repeat {
                guard try wire.string("snapshotId") == id, try wire.string("atCursor") == cursor else { throw ConnectError.protocolMismatch }
                for item in try wire.array("documents") {
                    guard let object = item.objectValue else { throw ConnectError.protocolMismatch }
                    rows.append(try .init(wire: object))
                }
                guard rows.count <= 1000 else { throw ConnectError.protocolMismatch }
                guard let page = wire["nextPage"]?.stringValue else { break }
                guard seenPages.insert(page).inserted else { throw ConnectError.protocolMismatch }
                response = try await authorized(path: "/connect/v1/snapshots/" + Self.query(id) + "?page=" + Self.query(page), generation: expected)
                try check(expected)
                if response.status == 410 { expired = true; break }
                guard response.status == 200 else { throw try ServerFailure(response) }; wire = try response.json
            } while true
            if expired { continue }
            try store.replaceSnapshot(rows, cursor: cursor); publish(); return
        }
        throw ConnectError.transport("Snapshots expired repeatedly; retrying when the connection is stable")
    }
    private func pullChanges(generation expected: UUID) async throws {
        guard let cursor = try store?.cursor() else { try await takeSnapshot(generation: expected); return }
        var after = cursor
        for _ in 0..<16 {
            let response = try await authorized(path: "/connect/v1/changes?after=" + Self.query(after) + "&wait=0&limit=100", generation: expected)
            try check(expected)
            if response.status == 410 { try await recoverCursor(response, generation: expected); return }
            try await consumeChanges(response, generation: expected)
            let wire = try response.json
            if wire["hasMore"]?.boolValue == false { return }
            let next = try wire.string("nextCursor"); guard next != after else { throw ConnectError.protocolMismatch }; after = next
        }
        throw ConnectError.protocolMismatch
    }
    private func consumeChanges(_ response: HTTPResponse, generation expected: UUID) async throws {
        if response.status == 410 { try await recoverCursor(response, generation: expected); return }
        guard response.status == 200 else { throw try ServerFailure(response) }
        let wire = try response.json
        guard wire["hasMore"]?.boolValue != nil else { throw ConnectError.protocolMismatch }
        try check(expected); try store?.applyChanges(SyncCodec.changes(wire), cursor: wire.string("nextCursor")); publish()
    }
    private func recoverCursor(_ response: HTTPResponse, generation expected: UUID) async throws {
        let failure = try ServerFailure(response)
        if failure.code == "cursor_ahead" || failure.code == "epoch_changed" {
            try suspend(.needsAuthorization, reason: "The ship may have been restored. Rotate its restore epoch, reconnect, and review pending drafts.", removeCredentials: true)
            throw ConnectError.restoreDetected
        }
        guard failure.code == "cursor_expired" || failure.code == "snapshot_expired" else { throw failure }
        try await takeSnapshot(generation: expected)
    }
    private func authorized(path: String, method: String = "GET", body: Data? = nil, generation expected: UUID) async throws -> HTTPResponse {
        try check(expected)
        guard let transport else { throw ConnectError.notConnected }
        let access = try await accessToken(generation: expected)
        let response = try await transport.send(path: path, method: method, body: body, token: access, form: false)
        try check(expected)
        guard response.status == 401 else { return response }
        if credentials?.access == access { try await refresh(generation: expected) }
        guard let token = credentials?.access else { throw ConnectError.unauthorized }
        let retry = try await transport.send(path: path, method: method, body: body, token: token, form: false)
        try check(expected)
        if retry.status == 401 { try suspend(.revoked, reason: "This app’s access was revoked. Your unsent drafts are available for recovery.", removeCredentials: true); throw ConnectError.unauthorized }
        return retry
    }
    private func accessToken(generation expected: UUID) async throws -> String {
        try check(expected)
        guard let credentials else { throw ConnectError.notConnected }
        if credentials.refreshInFlight && refreshTask == nil {
            try suspend(.needsAuthorization, reason: "Credential refresh was interrupted. Connect again.", removeCredentials: false); throw ConnectError.unauthorized
        }
        if credentials.accessExpires.timeIntervalSince(clock()) <= 20 || refreshTask != nil { try await refresh(generation: expected) }
        try check(expected); guard let access = self.credentials?.access else { throw ConnectError.unauthorized }; return access
    }
    private func refresh(generation expected: UUID) async throws {
        try check(expected)
        if let task = refreshTask { try await task.value; try check(expected); return }
        let task = Task { try await self.performRefresh(generation: expected) }
        refreshTask = task
        do { try await task.value; try check(expected); refreshTask = nil }
        catch { if generation == expected { refreshTask = nil }; throw error }
    }
    private func performRefresh(generation expected: UUID) async throws {
        try check(expected)
        guard var current = credentials, let key, let transport else { throw ConnectError.notConnected }
        guard !current.refreshInFlight else { throw ConnectError.unauthorized }
        current.refreshInFlight = true; try tokens.write(current.encoded(), key: key); credentials = current
        do {
            let body = HTTPTransport.form(["grant_type": "refresh_token", "client_id": configuration.clientID, "refresh_token": current.refresh])
            let response = try await transport.send(path: "/connect/oauth/token", method: "POST", body: body, token: nil, form: true)
            try check(expected)
            guard response.status == 200 else {
                let failure = try ServerFailure(response)
                if response.status == 400 && failure.code == "invalid_grant" {
                    try suspend(.revoked, reason: "This app’s access expired or was revoked. Recover drafts before reconnecting.", removeCredentials: true)
                    throw ConnectError.unauthorized
                }
                throw failure
            }
            let next = try decodeCredentials(response.json, account: current.account)
            guard next.grant == current.grant else { throw ConnectError.protocolMismatch }
            try tokens.write(next.encoded(), key: key); credentials = next
        } catch {
            if generation == expected && status != .revoked {
                try suspend(.needsAuthorization, reason: "The credential refresh response was lost. Connect again to continue safely.", removeCredentials: false)
            }
            throw error
        }
    }
    private func suspend(_ next: ConnectionStatus, reason: String, removeCredentials: Bool) throws {
        status = next; message = reason
        if removeCredentials, let key { try tokens.delete(key: key); credentials = nil }
        try store?.clearConfirmed()
        for var mutation in try store?.mutations() ?? [] {
            mutation.current = nil
            if mutation.acknowledged == nil { mutation.status = .needsAttention; mutation.message = reason }
            try store?.update(mutation)
        }
        publish()
    }
    public func disconnect() async throws {
        stopTasks(); let expected = generation; var failure: (any Error)?
        let previous = credentials, endpoint = transport
        // Local logout is durable before any network await or app termination.
        try suspend(.disconnected, reason: "Disconnected. Unsent drafts remain on this device for explicit recovery.", removeCredentials: true)
        if let previous, let endpoint {
            do {
                var response = try await endpoint.send(path: "/connect/oauth/revoke", method: "POST", body: Data("{}".utf8), token: previous.access, form: false)
                if response.status == 401 && !previous.refreshInFlight {
                    // Captured credentials exist only in this logout operation.
                    // Refresh once solely to revoke an expired session; never
                    // reinstall credentials or replay an ambiguous refresh.
                    let body = HTTPTransport.form(["grant_type": "refresh_token", "client_id": configuration.clientID, "refresh_token": previous.refresh])
                    let refreshed = try await endpoint.send(path: "/connect/oauth/token", method: "POST", body: body, token: nil, form: true)
                    guard refreshed.status == 200 else { throw try ServerFailure(refreshed) }
                    let next = try decodeCredentials(refreshed.json, account: previous.account)
                    guard next.grant == previous.grant else { throw ConnectError.protocolMismatch }
                    response = try await endpoint.send(path: "/connect/oauth/revoke", method: "POST", body: Data("{}".utf8), token: next.access, form: false)
                }
                guard response.status == 200 else { throw try ServerFailure(response) }
            }
            catch { failure = error }
        }
        if generation != expected && credentials != nil { throw CancellationError() }
        if let failure { throw failure }
    }
    public func resolveConflict(_ id: PendingMutationID, resolution: ConflictResolution) async throws -> UUID? {
        guard let store else { throw ConnectError.notConnected }
        let all = try store.mutations(); guard let selected = all.first(where: { $0.id == id }) else { throw ConnectError.invalidIdentifier }
        let family = all.filter { $0.collection == selected.collection && $0.documentID == selected.documentID }
        let latest = family.last ?? selected
        if resolution == .useRemote {
            try store.replaceMutations(removing: family.map(\.id), with: nil); publish(); return nil
        }
        guard credentials != nil, status == .online || status == .offline else { throw ConnectError.notConnected }
        let current = selected.current
        let documentID: UUID, revision: Revision?
        if resolution == .saveAsNewDocument {
            guard latest.draft != nil else { throw ConnectError.invalidJSON("A deletion has no draft to save") }
            documentID = UUID(); revision = nil
        } else {
            guard let current else { throw ConnectError.server(status: 409, code: "deleted", message: "The document is missing. Save the draft as a new document instead.") }
            documentID = selected.documentID; revision = current.revision
        }
        // The replacement is prepared and persisted before retiring old drafts.
        var replacement = StoredMutation(id: .init(rawValue: UUID()), collection: selected.collection, documentID: documentID, draft: latest.draft, expected: revision, createdAt: clock(), status: .pending)
        replacement.body = try replacement.requestBody()
        try store.replaceMutations(removing: family.map(\.id), with: replacement)
        publish(); pollTask?.cancel(); startSynchronization(); return documentID
    }
    func pendingForTesting() throws -> [StoredMutation] { try store?.mutations() ?? [] }
    private static func query(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))! }
    private func userMessage(_ error: any Error) -> String {
        if let failure = error as? ServerFailure { return failure.message }
        switch error {
        case ConnectError.accountChanged: return "This endpoint now identifies a different ship instance. Pair it explicitly before continuing."
        case ConnectError.restoreDetected: return "The ship’s restore epoch changed. Connect again and review pending drafts."
        case ConnectError.protocolMismatch: return "The ship returned an unsupported or inconsistent protocol response."
        case ConnectError.authorizationDenied: return "Connection was denied on the ship."
        case ConnectError.authorizationCancelled: return "Connection was cancelled."
        case ConnectError.storage(let message), ConnectError.transport(let message), ConnectError.invalidJSON(let message): return message
        default: return "The ship is unavailable. Pending edits remain on this device."
        }
    }
}
