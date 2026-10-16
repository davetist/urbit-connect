import Foundation
import CSQLite

/// Synchronous by design: one ConnectClient actor owns each connection.
final class LocalStore {
    private var database: OpaquePointer?
    private let url: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) throws {
        self.url = url
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(resources)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }; database = nil
            throw ConnectError.storage("Cannot open local database")
        }
        do {
            let version = try scalarInteger("PRAGMA user_version")
            guard version <= 2 else { throw ConnectError.storage("This cache requires a newer SDK") }
            try execute("PRAGMA journal_mode=WAL"); try execute("PRAGMA synchronous=FULL"); try execute("PRAGMA busy_timeout=3000")
            try execute("PRAGMA wal_autocheckpoint=64"); try execute("PRAGMA journal_size_limit=1048576")
            if version == 0 {
                try transaction {
                    try execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
                    try execute("CREATE TABLE documents (collection TEXT NOT NULL, id TEXT NOT NULL, wire BLOB NOT NULL, PRIMARY KEY(collection,id))")
                    try execute("CREATE TABLE outbox (id TEXT PRIMARY KEY, created REAL NOT NULL, wire BLOB NOT NULL, request_bytes INTEGER NOT NULL)")
                    try execute("PRAGMA user_version=2")
                }
            } else if version == 1 {
                try transaction {
                    try execute("ALTER TABLE outbox ADD COLUMN request_bytes INTEGER NOT NULL DEFAULT 0")
                    for mutation in try mutations() {
                        try statement("UPDATE outbox SET request_bytes=? WHERE id=?") { stmt in
                            try bind(try requestBytes(mutation), to: 1, in: stmt)
                            try bind(mutation.id.rawValue.uuidString, to: 2, in: stmt); try done(stmt)
                        }
                    }
                    try execute("PRAGMA user_version=2")
                }
            }
            try protectFiles()
        } catch { sqlite3_close(database); database = nil; throw error }
    }
    deinit { if let database { sqlite3_close(database) } }
    private func protectFiles() throws {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.complete
            #endif
            try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
        }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func failure() -> ConnectError {
        let code = sqlite3_errcode(database)
        if code == SQLITE_FULL { return .storage("This device is out of storage. Existing drafts are retained; free space before trying again.") }
        return .storage("Local storage is unavailable (SQLite \(code)). Existing drafts are retained.")
    }
    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else { throw failure() }
        defer { sqlite3_finalize(pointer) }; return try body(pointer)
    }
    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else { throw failure() }
    }
    private func bind(_ value: Data, to index: Int32, in statement: OpaquePointer) throws {
        let result = value.withUnsafeBytes { bytes in sqlite3_bind_blob64(statement, index, bytes.baseAddress, UInt64(bytes.count), transient) }
        guard result == SQLITE_OK else { throw failure() }
    }
    private func bind(_ value: Int, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else { throw failure() }
    }
    private func done(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    private func blob(_ statement: OpaquePointer, column: Int32 = 0) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        if sqlite3_get_autocommit(database) == 0 { return try body() }
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func scalarInteger(_ sql: String) throws -> Int {
        try statement(sql) { stmt in
            guard sqlite3_step(stmt) == SQLITE_ROW else { throw failure() }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }
    func metadata(_ key: String) throws -> Data? {
        try statement("SELECT value FROM meta WHERE key=?") { stmt in
            try bind(key, to: 1, in: stmt)
            switch sqlite3_step(stmt) { case SQLITE_ROW: return blob(stmt); case SQLITE_DONE: return nil; default: throw failure() }
        }
    }
    func setMetadata(_ key: String, value: Data?) throws {
        if let value {
            try statement("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value") { stmt in
                try bind(key, to: 1, in: stmt); try bind(value, to: 2, in: stmt); try done(stmt)
            }
        } else {
            try statement("DELETE FROM meta WHERE key=?") { stmt in try bind(key, to: 1, in: stmt); try done(stmt) }
        }
    }
    func enqueue(_ mutation: StoredMutation) throws {
        let wire = try mutation.encoded(), bytes = try requestBytes(mutation)
        try transaction {
            try statement("INSERT INTO outbox(id,created,wire,request_bytes) VALUES(?,?,?,?)") { stmt in
                try bind(mutation.id.rawValue.uuidString, to: 1, in: stmt)
                guard sqlite3_bind_double(stmt, 2, mutation.createdAt.timeIntervalSince1970) == SQLITE_OK else { throw failure() }
                try bind(wire, to: 3, in: stmt); try bind(bytes, to: 4, in: stmt); try done(stmt)
            }
        }
    }
    private func requestBytes(_ mutation: StoredMutation) throws -> Int { try (mutation.body ?? mutation.requestBody()).count }
    func update(_ mutation: StoredMutation) throws {
        try transaction {
            let bytes = try requestBytes(mutation)
            try statement("UPDATE outbox SET wire=?,request_bytes=? WHERE id=?") { stmt in
                try bind(mutation.encoded(), to: 1, in: stmt); try bind(bytes, to: 2, in: stmt)
                try bind(mutation.id.rawValue.uuidString, to: 3, in: stmt); try done(stmt)
            }
        }
    }
    func removeMutation(_ id: PendingMutationID) throws {
        try statement("DELETE FROM outbox WHERE id=?") { stmt in try bind(id.rawValue.uuidString, to: 1, in: stmt); try done(stmt) }
    }
    func mutations() throws -> [StoredMutation] {
        try statement("SELECT wire FROM outbox ORDER BY rowid") { stmt in
            var records: [StoredMutation] = []
            while true {
                switch sqlite3_step(stmt) {
                case SQLITE_ROW: records.append(try StoredMutation.decode(blob(stmt)))
                case SQLITE_DONE: return records
                default: throw failure()
                }
            }
        }
    }
    private func insert(_ document: ConnectDocument, replace: Bool) throws {
        let suffix = replace ? " ON CONFLICT(collection,id) DO UPDATE SET wire=excluded.wire" : ""
        try statement("INSERT INTO documents(collection,id,wire) VALUES(?,?,?)" + suffix) { stmt in
            try bind(document.collection, to: 1, in: stmt); try bind(document.id.uuidString, to: 2, in: stmt)
            try bind(JSONValue.object(document.wire).encoded(maxDepth: 24), to: 3, in: stmt); try done(stmt)
        }
    }
    func replaceSnapshot(_ documents: [ConnectDocument], cursor: String) throws {
        try transaction {
            try execute("DELETE FROM documents")
            for document in documents { try insert(document, replace: false) }
            try setMetadata("cursor", value: Data(cursor.utf8))
            try setMetadata("hydrated", value: Data("true".utf8))
        }
    }
    func applyChanges(_ changes: [RemoteChange], cursor: String) throws {
        try transaction {
            for change in changes {
                switch change {
                case .put(let document): try insert(document, replace: true)
                case .delete(let collection, let id):
                    try statement("DELETE FROM documents WHERE collection=? AND id=?") { stmt in
                        try bind(collection, to: 1, in: stmt); try bind(id.uuidString, to: 2, in: stmt); try done(stmt)
                    }
                }
            }
            try setMetadata("cursor", value: Data(cursor.utf8))
        }
    }
    func documents() throws -> [ConnectDocument] {
        try statement("SELECT wire FROM documents ORDER BY collection,id") { stmt in
            var result: [ConnectDocument] = []
            while true {
                switch sqlite3_step(stmt) {
                case SQLITE_ROW:
                    guard let wire = try JSONValue.parse(blob(stmt), maxDepth: 24).objectValue else { throw ConnectError.storage("Corrupt document") }
                    result.append(try ConnectDocument(wire: wire))
                case SQLITE_DONE: return result
                default: throw failure()
                }
            }
        }
    }
    func cursor() throws -> String? { try metadata("cursor").map { String(decoding: $0, as: UTF8.self) } }
    func isHydrated() throws -> Bool { try metadata("hydrated") != nil }
    func replaceMutations(removing ids: [PendingMutationID], with replacement: StoredMutation?) throws {
        try transaction {
            for id in ids { try removeMutation(id) }
            if let replacement { try enqueue(replacement) }
        }
    }
    func completeAcknowledged(_ mutation: StoredMutation) throws {
        guard let revision = mutation.acknowledged else { throw ConnectError.storage("Missing acknowledgement") }
        try transaction {
            let all = try mutations()
            try removeMutation(mutation.id)
            for var child in all where child.dependsOn == mutation.id {
                child.dependsOn = nil; child.expected = revision
                child.body = try child.requestBody(); try update(child)
            }
        }
    }
    func clearConfirmed() throws {
        try transaction { try execute("DELETE FROM documents"); try setMetadata("cursor", value: nil); try setMetadata("hydrated", value: nil) }
    }
}

enum RemoteChange: Sendable { case put(ConnectDocument), delete(collection: String, id: UUID) }
