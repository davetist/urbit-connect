import CSQLite
import SQLiteFaultHelper
import Foundation
import Testing
@testable import UrbitConnect

@Suite(.serialized) struct StorageRecoveryTests {
    func sql(_ url: URL, _ body: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?; #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let database = try #require(db); defer { sqlite3_close(database) }; try body(database)
    }
    func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ConnectError.storage("Test SQL failed") }
    }
    func seedSchemaOne(_ url: URL, rows: [StoredMutation]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sql(url) { db in
            try execute(db, "PRAGMA journal_mode=WAL; CREATE TABLE meta(key TEXT PRIMARY KEY,value BLOB NOT NULL); CREATE TABLE documents(collection TEXT,id TEXT,wire BLOB,PRIMARY KEY(collection,id)); CREATE TABLE outbox(id TEXT PRIMARY KEY,created REAL NOT NULL,wire BLOB NOT NULL); PRAGMA user_version=1; BEGIN")
            var statement: OpaquePointer?; #expect(sqlite3_prepare_v2(db, "INSERT INTO outbox VALUES(?,0,?)", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for row in rows {
                sqlite3_reset(statement)
                let wire = try row.encoded()
                sqlite3_bind_text(statement, 1, row.id.rawValue.uuidString, -1, transient)
                _ = wire.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
                #expect(sqlite3_step(statement) == SQLITE_DONE)
            }
            try execute(db, "COMMIT")
        }
    }
    @Test func interruptedMigrationRollsBackVersionAndCanRetryWithExactPendingBytes() throws {
        let url = CapacityTests().url(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var queued = try CapacityTests().mutation(); queued.body = Data("  ".utf8) + queued.body! + Data("\n".utf8)
        try seedSchemaOne(url, rows: [queued])
        #expect(url.resolvingSymlinksInPath().path.withCString { connect_test_vfs_install($0) } == SQLITE_OK)
        defer { connect_test_vfs_reset() }
        connect_test_vfs_fail_after(0)
        #expect(throws: ConnectError.self) { try LocalStore(url: url) }
        try sql(url) { db in
            var statement: OpaquePointer?; #expect(sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            #expect(sqlite3_step(statement) == SQLITE_ROW); #expect(sqlite3_column_int(statement, 0) == 1)
            #expect(sqlite3_exec(db, "SELECT request_bytes FROM outbox", nil, nil, nil) != SQLITE_OK)
        }
        #expect(try LocalStore(url: url).mutations() == [queued])
        #expect(try LocalStore(url: url).mutations().first?.body == queued.body)
    }
    @Test func legacyOverBudgetQueueIsPreservedAndCanReleaseCapacityWithoutEviction() throws {
        let url = CapacityTests().url(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let rows = try (0..<1001).map { _ in try CapacityTests().mutation(bytes: 17000) }
        try seedSchemaOne(url, rows: rows)
        let store = try LocalStore(url: url)
        #expect(try store.mutations() == rows)
        #expect(throws: ConnectError.self) { try store.enqueue(CapacityTests().mutation()) }
        #expect(try store.mutations().map(\.id) == rows.map(\.id))
        // Completing old work releases both budgets. It never silently drops rows.
        for row in rows.prefix(20) { try store.removeMutation(row.id) }
        try store.enqueue(CapacityTests().mutation())
        #expect(try LocalStore(url: url).mutations().count == 982)
        #expect(try LocalStore(url: url).mutations().dropLast().map(\.id) == rows.dropFirst(20).map(\.id))
    }
    @Test func schemaOneMigrationPreservesPendingBytesAndCanBeRepeated() throws {
        let url = CapacityTests().url(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var queued = try CapacityTests().mutation()
        queued.body = Data("  ".utf8) + queued.body! + Data("\n".utf8)
        let wire = try queued.encoded()
        try sql(url) { db in
            try execute(db, "CREATE TABLE meta(key TEXT PRIMARY KEY,value BLOB NOT NULL); CREATE TABLE documents(collection TEXT,id TEXT,wire BLOB,PRIMARY KEY(collection,id)); CREATE TABLE outbox(id TEXT PRIMARY KEY,created REAL NOT NULL,wire BLOB NOT NULL); PRAGMA user_version=1")
            var statement: OpaquePointer?; #expect(sqlite3_prepare_v2(db, "INSERT INTO outbox VALUES(?,0,?)", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, queued.id.rawValue.uuidString, -1, transient)
            _ = wire.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
            #expect(sqlite3_step(statement) == SQLITE_DONE)
        }
        for _ in 0..<2 {
            let store = try LocalStore(url: url)
            #expect(try store.mutations() == [queued]); #expect(try store.mutations().first?.body == queued.body)
        }
    }
    @Test func unsupportedDowngradeLeavesTheNewerDatabaseUnchanged() throws {
        let url = CapacityTests().url(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sql(url) { try execute($0, "CREATE TABLE future(value TEXT); INSERT INTO future VALUES('keep'); PRAGMA user_version=99") }
        let before = try Data(contentsOf: url)
        #expect(throws: ConnectError.storage("This cache requires a newer SDK")) { try LocalStore(url: url) }
        #expect(try Data(contentsOf: url) == before)
        #expect(!FileManager.default.fileExists(atPath: url.path + "-wal"))
    }
    @Test func fullAndInterruptedWALWritesRollBackWithoutLosingDraftsOrCursor() throws {
        for writes in [0, 1] {
            let url = CapacityTests().url(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            #expect(url.resolvingSymlinksInPath().path.withCString { connect_test_vfs_install($0) } == SQLITE_OK)
            defer { connect_test_vfs_reset() }
            do {
                let store = try LocalStore(url: url), queued = try CapacityTests().mutation()
                try store.enqueue(queued)
                let doc = ConnectDocument(id: UUID(), collection: "notes", data: ["text": .string("Confirmed")], revision: try Revision("1"), updatedAt: "2026-10-13T00:00:00Z")
                try store.replaceSnapshot([doc], cursor: "1:1:1")
                try #require(connect_test_vfs_tracked_count() >= 2, "The test VFS must wrap the actual database and WAL files")
                connect_test_vfs_fail_after(Int32(writes))
                #expect(throws: ConnectError.self) { try store.enqueue(CapacityTests().mutation()) }
                #expect(try store.mutations() == [queued])
                #expect(try store.documents() == [doc]); #expect(try store.cursor() == "1:1:1")
                connect_test_vfs_fail_after(Int32(writes))
                #expect(throws: ConnectError.self) { try store.replaceSnapshot([], cursor: "1:1:2") }
                #expect(try store.documents() == [doc]); #expect(try store.cursor() == "1:1:1")
                try store.enqueue(CapacityTests().mutation())
                #expect(try store.mutations().count == 2)
            }
            #expect(try LocalStore(url: url).mutations().count == 2)
        }
    }
    @Test func conflictReplacementWorksAtCapacityAndFailureRestoresTheFamily() throws {
        let url = CapacityTests().url(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalStore(url: url)
        for _ in 0..<1000 { try store.enqueue(CapacityTests().mutation()) }
        let before = try store.mutations(), replacement = try CapacityTests().mutation()
        try store.replaceMutations(removing: [before[0].id], with: replacement)
        #expect(try store.mutations().count == 1000)
        let full = try store.mutations()
        #expect(throws: ConnectError.self) { try store.replaceMutations(removing: [replacement.id], with: CapacityTests().mutation(bytes: 16 * 1024 * 1024 + 1)) }
        #expect(try store.mutations().map(\.id) == full.map(\.id))
    }
    @Test func sustainedOutboxChurnBoundsWALGrowth() throws {
        let url = CapacityTests().url(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalStore(url: url)
        for _ in 0..<1500 { let next = try CapacityTests().mutation(bytes: 16384); try store.enqueue(next); try store.removeMutation(next.id) }
        let bytes = try FileManager.default.attributesOfItem(atPath: url.path + "-wal")[.size] as! Int
        #expect(bytes <= 1_400_000); #expect(try store.mutations().isEmpty)
    }
}
