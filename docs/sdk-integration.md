# Integrating the Swift SDK

Use the project root as a local Swift package, or add `sdk/swift` as the existing nested local package. Both export `UrbitConnect`. The candidate version is `0.2.0-alpha.1`, protocol 1, with iOS 18+/macOS 15+ compile floors; actual qualification is the named Simulator runtime. A public Git tag/repository is pending authorization and provenance, so the documented workflow uses a local path.

Prerequisites: Xcode/Swift 6, an installed/configured Connect desk over trusted HTTPS, the ability to register your own known app through the ship manager, and an app callback scheme. No developer backend, app secret, owner-code injection, staff enrollment or paid Apple account is needed for the Simulator flow.

Configure your exact client ID/callback in both the native target and the ship’s manager. Registration is separate from consent. Use `SystemAuthorizationPresenter` with the app window; the ship’s system-browser page handles owner login and explicit scopes. Each app retains its own endpoint/instance and scoped session. Public IDs/custom schemes do not prove native publisher identity.

```swift
import UrbitConnect

let configuration = try ConnectConfiguration(
    clientID: "my-notes-app",
    redirectURI: URL(string: "org.example.mynotes:/oauth/callback")!
)
let client = try ConnectClient(
    configuration: configuration,
    persistenceDirectory: applicationSupport.appending(path: "ConnectNotes")
)
let account = try await client.connect(
    to: URL(string: "https://your-ship.example")!,
    presentation: SystemAuthorizationPresenter(anchor: window)
)
let id = UUID()
let pending = try await client.put(
    collection: "notes", id: id,
    data: ["formatVersion": .number("1"), "text": .string("A note")],
    expectedRevision: nil
)
for await state in await client.observe(collection: "notes") {
    // Show confirmed documents plus pending drafts and an accurate status.
    // A pending enqueue is not a ship acknowledgement.
}
```

Call `resume()` at startup and `setForeground(_:)` on scene transitions. Use `documents(in:)`/`get(collection:id:)` for confirmed cached reads. Updating/deleting uses the displayed `Revision`; creates use nil. A 16 KiB document rejection or local capacity/storage failure must leave editable input intact. `put`/`delete` return only after durable queueing. The outbox retains exact bytes/IDs on uncertain retries; do not create a new ID merely because the response was lost.

Expose `CollectionState.connection`, `message`, `hydrated`, `pending` and each mutation’s status. Conflicts and restore/revocation drafts require deliberate choices through `resolveConflict(_:resolution:)`; preserve both versions. `useRemote` retires the local family, `retryWithCurrent` uses the last displayed remote revision and can conflict again, and `saveAsNewDocument` creates a distinct document. `recoveryDrafts()` reads the selected account’s drafts. `retainedAccounts()` lists older local accounts; `exportDrafts(archiveID:)` produces a user-requested JSON data export without credentials. It contains document bodies and must be shared only when the user requests it. `removeRetainedAccount(archiveID:confirmation:)` requires that same archive ID and refuses the selected account. Read/export before deliberate removal or uninstalling. `disconnect()` removes device credentials and attempts ship revocation; if unreachable, revoke the session in the owner manager.

Parse an entered address with `ConnectEndpoint`. If `requiresConfirmation` is true, show `origin` for explicit confirmation before calling `connect`; only the known `/apps/connect/` manager path is recognized. `preflight(origin:expected:)` checks information without consent, credentials or pairing changes. It distinguishes `missingDesk`, `notConfigured`, `unsupportedProtocol`, TLS/network errors and pinned account/generation changes. Successful malformed responses remain errors. Handle `localCapacity` by retaining editable input and presenting the relevant count, byte or account limit.

Lossless `JSONObject`/`JSONValue` values accept generic object schemas. Preserve unknown documents instead of coercing them to your app’s schema. A JSON number spelling is retained; revisions and restore generations are bounded decimal strings, not machine integers. Treat generations as opaque equality identifiers.

`tests/consumers/swift` is a compile-time public-interface consumer with a distinct notes schema. It has no `@testable` SDK import, copied TodoStore or private hooks. It is authored here and **does not satisfy the independent-developer trial**. An unfamiliar developer must create their own distinct-schema app from these instructions and record registration, system-browser approval, CRUD, conflict and revocation against their authorized test setup. Target the first round trip within half a day after ship/HTTPS/Xcode prerequisites are ready; report setup time separately.
