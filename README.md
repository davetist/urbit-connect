# %connect

A personal app backend on your Urbit ship, with a native Swift SDK and an iOS todo example. Each approved app gets its own document namespace. The ship owner can inspect, edit, export, import, erase, and revoke access from `/apps/connect/`.

**Reliability alpha candidate:** desk/Swift/Todo version `0.2.0-alpha.1`, protocol 1, SQLite schema 2. The alpha adds restart recovery, bounded offline queues, retained-draft recovery, safer manager actions and installation tooling. See the [alpha evidence](artifacts/alpha/report.md) and [qualification matrix](tests/acceptance/alpha-matrix.md). The historical [210-case prototype report](artifacts/acceptance/report.md) is separate from final alpha qualification. Real-host soak, independent operator/developer trials and release ownership/notices remain gates. This is a local source/Simulator deliverable; public native distribution is deferred.

The ship can read documents. The SDK sends data directly to the paired HTTPS ship endpoint, without a developer data service. An app that can display your data can also copy it; an SDK cannot prevent a malicious app publisher from doing that. HTTPS protects transport, and `%connect` enforces app permissions on the ship.

## Run the isolated alpha

The reproducible development setup targets Apple Silicon macOS with Xcode 26.6, its command-line tools, Python 3.10+, Node 22.12+ and npm, and Homebrew. It downloads the pinned Vere 4.6 runtime, kernel-408 pill, Caddy, and iOS 26.5 Simulator runtime when missing. Allow roughly 15–20 GB for the runtime, Simulator, fake piers, and build products.

```sh
python3 scripts/setup.py --install-tools
```

Setup creates an owned `.work/alpha` fixture and dedicated **Connect Alpha** Simulators. Its local certificate is trusted only in those Simulators and the project’s Firefox profile. An existing demo is preserved. No production ship, global certificate store, Apple account, or paid service is needed.

To use it yourself, open `examples/ios-todo/ConnectTodo.xcodeproj`, select the `ConnectTodo` scheme and dedicated Simulator, and run. Enter the HTTPS address printed by setup, tap **Connect with Urbit**, log in to the fake ship in the system browser, and approve. Ports are bound to the checkout by `.work/alpha/targets.json`. The disposable owner login code is in the private `.work/alpha/dev/auth.json` file; do not put it in app configuration or source control. Run `python3 scripts/open_owner_ui.py` to open the manager in the dedicated Firefox profile. Normal host browsers deliberately do not trust the test certificate.

Create **Personal**, add **Buy milk**, and wait for **Saved on your ship**. That status means the ship acknowledged the write; queued offline edits have a different status. A conflicting edit keeps both versions for an explicit decision.

The acceptance commands below reset the disposable sample namespace and exercise revocation. After running them, use **Reconnect with Urbit** to approve a new session. Cleanup stops the test environment; run setup again before opening the app.

```sh
python3 scripts/check.py --all
python3 scripts/package_desk.py --verify-install
python3 scripts/cleanup.py
```

The local desk archive is `dist/connect-0.2.0-alpha.1.tgz`, with a SHA-256 sidecar and file manifest. `scripts/release_check.py --build` also creates SDK, Todo source and complete-source archives twice and compares their hashes. See [development](docs/development.md) for check prerequisites, [install](docs/install.md) and [update](docs/update.md) for real ships, [operations](docs/operations.md) for restore, and [security](docs/security.md) for the trust model. Owner registration is local to the ship; registering Todo is an explicit sample option.

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

`put` and `delete` return after durable local queueing. Use the observation stream to distinguish pending writes from server acknowledgement. Updates require the displayed document’s `Revision`; creates use `nil`. Call `resume()` at startup and `setForeground(_:)` as scene activity changes. `disconnect()` durably removes local credentials before attempting ship revocation; a failed remote cleanup requires owner revocation. Preserve recoverable drafts and offer explicit `resolveConflict` choices, as the example does. Each account accepts at most 1,000 pending mutations or 16 MiB of encoded requests; rejection preserves existing drafts and editable input.

Documents use `JSONObject` / `JSONValue`, with lossless numeric spellings and strict validation. The SDK has no todo-specific schema. The example owns `TodoList` and `TodoTask`; unknown documents remain visible as unsupported data and are never silently rewritten.

The pairing identity is the HTTPS issuer plus persistent instance ID. The displayed ship name is asserted by that endpoint; this prototype does not independently verify global ship ownership or provide a federated identity token to developer backends.

## Local resource authorization

The opt-in [resource integration contract](docs/resource-integrations.md) lets a local Gall agent use Connect owner consent, PKCE codes and live revocation while managing its own data and wire protocol. Ordinary document clients are unchanged. The included [grant-probe](integrations/grant-probe/desk/app/grant-probe.hoon) test consumer demonstrates the reusable authorization contract.
