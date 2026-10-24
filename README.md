# %connect

A personal app backend on your Urbit ship, with a native Swift SDK and an iOS todo example. Each approved app gets its own document namespace. The ship owner can inspect, edit, export, import, erase, and revoke access from `/apps/connect/`.

**Local source release:** desk/Swift/Todo version `0.2.0-alpha.1`, protocol 1, SQLite schema 2. Connect provides restart recovery, durable offline queues, retained-draft recovery, owner management and installation tooling. Artificial document/storage, app/session and SDK draft/account quotas are removed; [specific parser, concurrency and replay controls](docs/capacity.md) remain. Daily use does not require a soak, tester quota or independent signoff. Historical reports remain [observations](tests/acceptance/alpha-matrix.md), not a qualification verdict. Public native distribution is separate.

The [readiness evidence](docs/current-readiness.md) separates older observations from the 2026-10-24 current-source SDK, native document and iOS Simulator Todo checks. Physical-device behavior remains a separate claim.

The ship can read documents. The SDK sends data directly to the paired HTTPS ship endpoint, without a developer data service. An app that can display your data can also copy it; an SDK cannot prevent a malicious app publisher from doing that. HTTPS protects transport, and `%connect` enforces app permissions on the ship.

## Install and update on your ship

Follow [installation](docs/install.md) for an authorized ship with the compatible runtime/kernel and a reachable HTTPS endpoint. Open `/apps/connect/` as its owner, configure the exact HTTPS origin, and register the intended client or resource integration. Follow [updates](docs/update.md) to preserve grants, documents and local drafts; [operations](docs/operations.md) covers backup and restore generation handling.

For Urbitwarden, use the separate [Urbitwarden repository](https://github.com/davetist/urbit-bitwarden) and its official-client instructions. Connect owns generic authorization; the Urbitwarden desk owns the vault API and encrypted vault data.

Build and verify the local source packages without booting a ship or running a test suite:

```sh
python3 scripts/release_check.py --build
python3 scripts/release_check.py --verify release/manifest.json
```

The desk archive is `dist/connect-0.2.0-alpha.1.tgz`, with a SHA-256 sidecar and file manifest. The build also creates SDK, Todo source and complete-source archives twice and compares their hashes. These are local source artifacts, not a deployment or signed native distribution. The [release notes](release/README.md) describe artifact integrity and informational observations.

The continuing direction is no synthetic or soak tests unless the owner explicitly changes it. Default verification uses source review, typechecking/builds and deterministic packaging; actual official-client workflows require an authorized target. The former fake-ship setup and Todo walkthrough are retained as a [historical reference](docs/historical/isolated-alpha.md).

## Use the Swift SDK

Add the project root or `sdk/swift` as a local Swift package dependency and import `UrbitConnect`. The package targets iOS 18+ and macOS 15+. Configure your app’s custom callback scheme and register its exact client ID and callback URI in the ship’s Connect manager. Client IDs are public identifiers, not secrets or verified publisher identities. The [integration guide](docs/sdk-integration.md) and distinct-schema [notes consumer](tests/consumers/swift) use public interfaces.

```swift
import UrbitConnect

let configuration = try ConnectConfiguration(
    clientID: "my-todo-app",
    redirectURI: URL(string: "org.example.mytodo:/oauth/callback")!
)
let client = try ConnectClient(
    configuration: configuration,
    persistenceDirectory: applicationSupport.appending(path: "UrbitConnect")
)
let account = try await client.connect(
    to: URL(string: "https://my-ship.example")!,
    presentation: SystemAuthorizationPresenter(anchor: window)
)
let id = UUID()
try await client.put(
    collection: "lists", id: id,
    data: ["title": .string("Personal"), "tasks": .array([])],
    expectedRevision: nil
)
for await state in await client.observe(collection: "lists") {
    // Render confirmed documents, pending drafts, conflicts and connection state.
}
```

`put` and `delete` return after durable local queueing. Use the observation stream to distinguish pending writes from server acknowledgement. Updates require the displayed document’s `Revision`; creates use `nil`. Call `resume()` at startup and `setForeground(_:)` as scene activity changes. `disconnect()` durably removes local credentials before attempting ship revocation; a failed remote cleanup requires owner revocation. Preserve recoverable drafts and offer explicit `resolveConflict` choices, as the example does. There is no fixed outbox or retained-account quota. Real storage failures preserve queued drafts and editable input.

Documents use `JSONObject` / `JSONValue`, with lossless numeric spellings and strict validation. The SDK has no todo-specific schema. The example owns `TodoList` and `TodoTask`; unknown documents remain visible as unsupported data and are never silently rewritten.

The pairing identity is the HTTPS issuer plus persistent instance ID. The displayed ship name is asserted by that endpoint; this prototype does not independently verify global ship ownership or provide a federated identity token to developer backends.

## Local resource authorization

The opt-in [resource integration contract](docs/resource-integrations.md) lets a local Gall agent use Connect owner consent, PKCE codes and live revocation while managing its own data and wire protocol. Ordinary document clients are unchanged. The included [grant-probe](integrations/grant-probe/desk/app/grant-probe.hoon) test consumer demonstrates the reusable authorization contract.
