import Foundation
import UrbitConnect

/// Compile-time integration of a distinct schema through public SDK interfaces.
public actor NotesConsumer {
    private let client: ConnectClient
    public init(directory: URL) throws {
        client = try ConnectClient(configuration: .init(clientID: "connect-notes-alpha", redirectURI: URL(string: "org.example.connect.notes:/oauth/callback")!), persistenceDirectory: directory)
    }
    public func connect(to origin: URL, presentation: any AuthorizationPresenter) async throws -> ConnectAccount {
        try await client.connect(to: origin, presentation: presentation)
    }
    public func resume() async throws -> ConnectAccount? { try await client.resume() }
    public func save(id: UUID, text: String, revision: Revision?) async throws -> PendingMutationID {
        try await client.put(collection: "notes", id: id, data: Self.document(text: text), expectedRevision: revision)
    }
    public func delete(id: UUID, revision: Revision) async throws -> PendingMutationID {
        try await client.delete(collection: "notes", id: id, expectedRevision: revision)
    }
    public func observe() async -> AsyncStream<CollectionState> { await client.observe(collection: "notes") }
    public func foreground(_ active: Bool) async { await client.setForeground(active) }
    public func resolve(_ id: PendingMutationID, with choice: ConflictResolution) async throws -> UUID? {
        try await client.resolveConflict(id, resolution: choice)
    }
    public func revoke() async throws { try await client.disconnect() }
    public static func document(text: String) -> JSONObject { ["formatVersion": .number("1"), "text": .string(text)] }
}
