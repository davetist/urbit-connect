# %connect iOS Todo Prototype Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` for sequential implementation. Use `superpowers:subagent-driven-development` only if the user selects delegation. Track steps with the checkboxes below. The original request authorized planning only. The subsequent user instruction authorized implementation and isolated verification; commits, production ship changes, and publication remain unauthorized.

**Goal:** Deliver an actual native iOS todo app using a reusable SDK to authorize against `%connect`, persist and synchronize documents on the user's ship, and let the owner inspect, export, edit, and revoke access to that data.

**Architecture:** One versioned Gall agent owns the generic document store and app grants, exposed through a dedicated Eyre HTTP API. A bundled owner interface handles consent and management; a Swift package handles system-browser authorization, scoped tokens, SQLite cache/outbox, and synchronization. The todo app contains only its own data model and UI.

**Tech Stack:** Hoon/Gall/Eyre; TypeScript/Vite; Swift 6, SwiftUI, AuthenticationServices, Foundation/URLSession, CryptoKit, Security/Keychain, SQLite; Python integration harness and Playwright browser tests. iOS 18+ and SDK macOS 15+.

**Spec:** [Design and acceptance contract](../specs/2026-10-12-connect-design.md). Read it before implementation. Paths below are relative to `/absolute/project`.

## Global constraints

- The ship can read documents. HTTPS and server-enforced app permissions are required; host-blind E2EE is outside this prototype.
- Never pass the owner's cookie, login code, networking private key, or wallet key to the SDK or todo app.
- Trust the explicitly paired HTTPS endpoint; identify accounts by `(issuer, instanceId)`. Do not claim independent global verification of its ship name.
- Use one `%connect` agent; no todo-specific Hoon behavior and no developer data backend.
- Target iOS 18+; the SDK also supports macOS 15+ for native package tests.
- Access token lifetime: 10 minutes. Authorization code lifetime: 60 seconds. Pending consent lifetime: 5 minutes. Absolute refresh session lifetime: 30 days.
- Document/request/batch limits: 16 KiB / 256 KiB / 32 operations. JSON depth: 16. Collection name: `[a-z][a-z0-9-]{0,47}`. IDs: lower-case UUIDs. Revision and cursor counters are decimal strings.
- Per namespace: 1,000 live documents, 4 MiB payload, 10,000 unexpired receipts, 10,000 unexpired tombstones. Receipts/tombstones expire after 30 days. Global live payload: 16 MiB.
- Max 8 clients / 32 active sessions. Journal: 1,024 batches or 1 MiB per namespace. Snapshot: 60 seconds, one/session, four globally. Page limit: 100. Long poll: 25 seconds, one/session.
- Rate limits: 120 document requests/minute/session and 30 authorization starts/minute/client; at most 32 outstanding consent requests.
- Authentication and document mutation must use distinct owner/app authority checks. Revocation is checked before returning cached receipts, snapshot pages, or change results.
- Preserve unrelated projects and production piers. Prepare isolated runtime, certificates, and simulator resources as part of execution, then clean them up safely.
- No branch, commit, push, desk publication, external deployment, or developer-account enrollment is implied. Follow the user's Git instructions if these are later requested.

## Review focus

1. Connection loss after the ship committed a write must not duplicate a task or lose an optimistic edit. Covered by Tasks 3 and 6.
2. A normal local HTTP delivery or an EAuth visitor must never be mistaken for owner approval. Covered by Task 4.
3. Revocation during a pending poll, snapshot, or refresh must take effect at the next response, including cached success paths. Covered by Tasks 3, 4, and 7.
4. Snapshot pagination under concurrent edits, journal truncation, and old-backup restore must not silently skip or mix data. Covered by Tasks 3, 6, and 7.
5. An owner may edit JSON into an unknown todo schema; the example must retain and identify that data rather than crash or overwrite it. Covered by Tasks 5 and 6.

## Work sequence and delivery boundaries

| Task | Independently testable result | Depends on |
|---|---|---|
| 1 | Reproducible isolated Urbit + HTTPS + iOS test environment; empty desk installs | None |
| 2 | Versioned protocol fixtures and public SDK interface contract | 1 |
| 3 | Durable bounded document engine, HTTP storage routes, snapshot/delta protocol | 2 |
| 4 | Real owner consent, PKCE, scoped sessions, and revocation | 2, 3 |
| 5 | Ship-side management interface and validated export/import | 3, 4 |
| 6 | Reusable native SDK and complete SwiftUI todo consumer | 2–5 |
| 7 | End-to-end, restart, isolation, recovery, and visual acceptance evidence | 1–6 |

Task 3 is tested through an isolated test adapter until Task 4 supplies authentication. No unauthenticated development switch or grant-injection HTTP route may be included in the distributable desk. Do not demonstrate the product as complete until Task 7 passes.

## Planned file map

```text
connect/
  README.md
  toolchain.json                       # exact runtime/pill/kernel/build versions and hashes
  protocol/v1/openapi.yaml              # normative HTTP contract
  protocol/v1/fixtures/*.json           # shared valid/error/expiry/conflict fixtures
  desk/app/connect.hoon                # Gall state/lifecycle and event coordination
  desk/sur/connect.hoon                # versioned state and protocol nouns
  desk/lib/connect/auth.hoon           # code/token/session transitions
  desk/lib/connect/policy.hoon         # authority and resource limits
  desk/lib/connect/store.hoon          # atomic documents/receipts/journal/snapshots
  desk/lib/connect/http.hoon           # routes and strict JSON/HTTP translation
  desk/tests/connect/{store,auth,policy}.hoon
  desk/{desk.bill,desk.docket-0,sys.kelvin}
  desk/fil/connect/                    # reproducibly bundled web assets
  web/src/{main,api,consent,apps,documents,transfers}.ts
  web/src/styles.css
  web/tests/{consent,management}.spec.ts
  sdk/swift/Package.swift
  sdk/swift/Sources/UrbitConnect/
    ConnectClient.swift                # public actor and operation coordination
    Models.swift                       # generic wire/document models
    AuthorizationSession.swift         # AuthenticationServices adapter
    TokenStore.swift                   # Keychain implementation
    HTTPTransport.swift               # pinned-origin HTTPS client
    LocalStore.swift                   # SQLite confirmed state and outbox
    SyncEngine.swift                   # snapshot/poll/retry/conflict state machine
  sdk/swift/Tests/UrbitConnectTests/
    {Protocol,Authorization,LocalStore,SyncEngine}Tests.swift
  examples/ios-todo/
    ConnectTodo.xcodeproj
    ConnectTodo/{ConnectTodoApp,TodoModel,TodoStore,PairingView,ListsView,ListView,ConflictView}.swift
    ConnectTodoTests/TodoModelTests.swift
    ConnectTodoUITests/ConnectTodoUITests.swift
  scripts/{check,dev_ship,test_hoon,test_integration,package_desk,ios_test}.py
  tests/integration/{test_auth,test_documents,test_sync,test_lifecycle,test_limits}.py
  tests/acceptance/prototype-checklist.md
  docs/{protocol,development,security,operations}.md
```

Create configuration/lockfiles and support sources alongside their owning task when needed. Keep downloaded runtimes, piers, credentials, TLS keys, build products, screenshots, and local reports out of source control. Exact third-party versions and any base desk files must be established in Task 1, not guessed here.

## Task 1: Reproducible environment and installable empty desk

**Files:** `toolchain.json`, `desk/app/connect.hoon`, `desk/sur/connect.hoon`, desk manifests, `scripts/dev_ship.py`, `scripts/test_hoon.py`, `scripts/package_desk.py`, `scripts/ios_test.py`, `scripts/check.py`, `docs/development.md`, `.gitignore`.

**Interfaces:** `python3 scripts/dev_ship.py start --state-dir <marked-temp-dir>` returns nonsecret endpoint/process metadata. `stop --state-dir ...` only stops owned process identities. `python3 scripts/test_hoon.py --suite <name>` invokes the pinned runtime's actual test runner and fails if zero cases execute. `python3 scripts/ios_test.py --suite <name>` resolves one disposable Simulator and returns the underlying xcodebuild result.

- [x] Add a preflight that reports installed tool versions, simulator runtimes, and supported runtime/pill downloads without reading user credentials. Locate an existing runtime or obtain an official checksum-verified release; record immutable versions and hashes in `toolchain.json`.
- [x] Install a compatible iOS Simulator runtime and create a disposable simulator. Current evidence: Xcode 26.6 is installed; there are no simulator runtimes/devices; `urbit` is absent from PATH. Storage/download requirements belong to this task, not an unreported user prerequisite.
- [x] Implement the isolated fake-ship launcher with loopback networking, explicit owned ports, marked resource directory, clean shutdown, crash-test process handles, and readiness timeout. Refuse production paths and foreign process identities.
- [x] Prepare a reproducible HTTPS proxy using a maintained pinned implementation, a local certificate with the required loopback SANs, and test-only certificate trust confined to the disposable Simulator/browser profile. Verify normal TLS success and wrong/untrusted certificate failure. Never install global trust or disable validation.
- [x] Build a minimal installable `%connect` desk that reports protocol version and development identity. Prove raw Eyre route handling, identification of owner versus unauthenticated/foreign sessions, and bounded delayed HTTP responses on the pinned kernel. Resolve any API differences before freezing the next task's contract.
- [x] Wire the actual Hoon test runner and record its exact command in development docs; derive it from the selected runtime's shipped test tools. Add a deliberately failing assertion, observe failure, restore it, and observe a nonzero passing test count. Do not equate Hoon compilation with executed behavior.
- [x] Run `python3 scripts/check.py --suite environment` and `python3 scripts/package_desk.py --verify-install`. Pass means an empty packaged desk installs on a fresh isolated ship, HTTPS is trusted only in the test environments, and the iOS runtime can launch a blank test target. Record runtime/kernel/device versions.

**Exit:** environment is runnable with documented commands; no live ship or host trust settings have changed.

## Task 2: Freeze the protocol and reusable SDK surface

**Files:** `protocol/v1/openapi.yaml`, fixtures, `sdk/swift/Package.swift`, `Models.swift`, `ProtocolTests.swift`, `docs/protocol.md`.

**Wire types:** `Account {issuer,instanceId,ship,syncEpoch}`, `Grant {id,clientId,namespace,namespaceEpoch,scopes,sessionId}`, `Document {id,collection,data,revision,updatedAt}`, `Mutation {requestId,operations}`, `Commit {revision,results}`, `ChangePage {batches,nextCursor,hasMore}`, `SnapshotPage {snapshotId,atCursor,documents,nextPage}`. Each opaque cursor encodes `{syncEpoch,namespaceEpoch,revision}`. Wire `Account` maps to public Swift `ConnectAccount`, `Document` to `ConnectDocument`, revision to a string-backed `Revision`, JSON object to `JSONObject`, and queued mutation ID to UUID-backed `PendingMutationID`. `CollectionState` contains documents, draft overlays, hydration/connection status, and pending mutation/conflict/needs-attention states. Use decimal strings for revisions and a lossless, explicitly validated JSON representation rather than `[String: Any]`.

**Public Swift contract** (implemented in Task 6):

```swift
public actor ConnectClient {
    public func connect(to origin: URL, presentation: any AuthorizationPresenter) async throws -> ConnectAccount
    public func get(collection: String, id: UUID) async throws -> ConnectDocument?
    public func documents(in collection: String) async throws -> [ConnectDocument]
    public func put(collection: String, id: UUID, data: JSONObject,
                    expectedRevision: Revision?) async throws -> PendingMutationID
    public func delete(collection: String, id: UUID,
                       expectedRevision: Revision) async throws -> PendingMutationID
    public func observe(collection: String) async -> AsyncStream<CollectionState>
    public func disconnect() async throws
}
```

The `connect` presenter bridges MainActor system UI safely. `put`/`delete` return after local durable queueing, not remote acknowledgement. `CollectionState` includes confirmed records, pending overlays, per-operation status, and conflicts. `documents(in:)` reads the local authorized view; an observed hydration/sync status makes an empty cache distinct from an empty remote collection. Initializer takes `ConnectConfiguration(clientID,redirectURI,requestedScopes)` and an SDK-owned persistence location. Internal transport, clock, authorization presenter, and token-store protocols permit deterministic tests without leaking test controls into the production API.

**Endpoints:** `/connect/v1/info`; `/connect/oauth/{authorize,token,revoke}`; `/connect/v1/identity` (current account/grant); `/connect/v1/collections/{collection}/documents[/{id}]`; `/connect/v1/mutations`; `/connect/v1/changes`; `/connect/v1/snapshots[/{id}]`. Read/list paths are GET; mutations and snapshot creation are POST. The revoke endpoint revokes only the caller's current session. Owner-only routes under `/connect/owner/v1/` cover bootstrap/CSRF, registrations, grants, documents, snapshots, import validation/application, namespace erasure, and restore-epoch rotation.

- [x] Specify each route's method, authority, body, success status, bounded response, error, cache headers, and redirect policy. Include OAuth errors and a document error shape `{error:{code,message,requestId,retryAfterSeconds?}}`; define `conflict` details separately with authorized current record/tombstone state.
- [x] Add fixtures for create/update/delete, denied grants, missing/invalid scopes, conflict, revoked session, stale cursor, protocol mismatch, and multi-page snapshot. Test `testRevisionRoundTripAboveJavaScriptSafeInteger` using revision `9007199254740993`; it must remain a string without rounding.
- [x] Test `testNamespaceCannotBeSelectedByClientPayload`: input namespace/client overrides are rejected rather than changing the grant-derived target. Test limits and identifier encodings including slash, percent-encoded slash, traversal, empty string, Unicode, and mixed-case UUID.
- [x] Define the generic JSON subset and fixtures for duplicate keys, excessive depth, non-finite values, unsafe integers, 16 KiB/256 KiB boundaries, and UTF-8 byte size rather than character count.
- [x] Run `python3 scripts/check.py --suite protocol` and `swift test --package-path sdk/swift --filter ProtocolTests`. Pass means schema validation and Swift fixture decoding agree; capture meaningful initial failures before adding decoders/validators.

**Exit:** desk, web, and native implementation have one versioned contract. The todo model is not a protocol requirement.

## Task 3: Durable document engine and synchronization routes

**Files:** `desk/lib/connect/{store,policy,http}.hoon`, `desk/sur/connect.hoon`, `desk/app/connect.hoon`, `desk/tests/connect/{store,policy}.hoon`, `tests/integration/{test_documents,test_sync,test_lifecycle,test_limits}.py`.

**Interfaces:** pure store transitions consume `(state, verified-grant, now, mutation)` and return `(new-state, commit-or-error, change-batch?)`; reads consume only a verified authority. HTTP middleware obtains authority through the Task 4 adapter, never directly from JSON. All mutations, receipts, revisions, and emitted effects are coordinated within one Gall event. Snapshot handles bind namespace, session, epoch, revision, deadline, and an immutable view.

- [x] Write executed Hoon tests `create-read-update-delete`, `atomic-batch-conflict`, `duplicate-target-rejected`, `same-request-same-result`, `changed-body-same-request-rejected`, and `app-b-cannot-use-app-a-ids`; assert unchanged state on any failed batch.
- [x] Add `conflicting-edits-preserve-current`, `lost-response-retry-one-revision`, `reauthorized-retry-recovers-receipt`, `write-only-conflict-does-not-leak-body`, `unknown-revision-cannot-recreate-deleted`, and all size/count/depth quota tests. Test current operation scopes before duplicate receipt lookup; receipt keys include both epochs and namespace, not login session. Tests must fail for the intended behavior before adding the transitions.
- [x] Implement bounded generic storage, create-only/CAS writes, whole-batch validation, persistent receipts, tombstones, one-revision-per-batch changes, TTL cleanup, and capacity backpressure. Keep receipt responses compact and exclude secrets.
- [x] Implement consistent snapshots, paged change batches, expiry/gap responses, scoped pagination, long-poll cancellation/timeouts, and Behn cleanup. Test `snapshot-concurrent-write-no-gap`, `snapshot-page-cannot-cross-session`, `revocation-during-poll`, `journal-gap-returns-410`, and epoch mismatch.
- [x] Expose routes through the strict codec. Exercise them against the actual agent with a non-distributed test adapter and through authenticated sessions after Task 4. Verify malformed requests return errors without stopping the agent; no generic agent forwarding or private scry endpoints are added.
- [x] Test clean restart and controlled abrupt termination after an acknowledged commit using only the isolated ship. Reopen and verify records, receipts, and revisions. Add a synthetic prior state fixture and prove migration to the current state version preserves persistent contents while clearing pending polls/snapshots.
- [x] Run `python3 scripts/test_hoon.py --suite store` and `python3 scripts/test_integration.py --suite documents,sync,lifecycle,limits`. The harness must reject skipped/zero tests. Pass means exact fixture behavior and persistence are observed in a real isolated ship.

**Exit:** generic database/sync behavior works and survives restart; external use remains gated on Task 4 authentication.

## Task 4: Owner authorization, scoped credentials, and revocation

**Files:** `desk/lib/connect/{auth,policy,http}.hoon`, `desk/tests/connect/{auth,policy}.hoon`, `web/src/{consent,api,main}.ts`, `web/tests/consent.spec.ts`, `tests/integration/test_auth.py`, `docs/security.md`.

**Interfaces:** auth transitions implement `beginAuthorization`, `approveAuthorization`, `exchangeCode`, `rotateRefreshToken`, `authenticateAccessToken`, and `revokeSession` with the lifetimes and bindings in the spec. `approveAuthorization` requires verified local owner authority, matching pending nonce and CSRF context. Produces the verified grant consumed by Task 3.

- [x] Test owner-cookie absence, foreign EAuth identity, spoofed local-source HTTP request, forged Origin, missing CSRF, injected redirect, PKCE downgrade/wrong verifier, state mismatch, consumed/expired code, and changed client/redirect at token exchange. Invalid clients/redirects return local errors and are never redirected.
- [x] Implement owner-managed registration for the development client and independent second test client; use server-assigned namespaces. Render consent metadata as escaped text, with development/unverified status. New sessions need explicit approval; denied/cancelled flows issue no credentials.
- [x] Implement entropy-backed opaque secrets, digest lookup, single-use codes, access/session expiry, rotating refresh families, session-scoped rate limits, and bounded authorization requests. Never log bearer secrets or encode them in URLs. Test one concurrent refresh winner and fail-closed handling of a consumed token.
- [x] Add owner session/all-app revocation and client self-disconnect. Revoke pending polls and snapshots, enforce current grant status on duplicate receipts, and verify documents remain intact. Test that revoking one device does not revoke an independent device session.
- [x] Inspect and test every entry point: raw HTTP, direct poke/watch, scry, owner route, and package assets. Reject arbitrary requests that claim another app namespace or owner capability. Enforce no external CORS policy while independently checking all actual authority.
- [x] Use Playwright to prove login → consent → approve/deny in a browser, including anti-framing, no-store headers, escaped malicious app names, expired pending requests, and correct callback contents. No token may appear in browser history or console evidence.
- [x] Run `python3 scripts/test_hoon.py --suite auth,policy`, `python3 scripts/test_integration.py --suite auth,documents,sync`, and `npm --prefix web run test:e2e -- consent.spec.ts`.

**Exit:** a native-compatible public client can obtain and revoke a narrow grant without receiving owner credentials. Cookie/local-owner behavior has runtime evidence, not just source inspection.

## Task 5: Ship owner interface and data portability

**Files:** `web/src/{apps,documents,transfers,api,main}.ts`, `styles.css`, `web/tests/management.spec.ts`, associated owner routes in `http.hoon`, `docs/operations.md`.

**Interfaces:** owner routes call the same version-checked store transitions with owner authority; they cannot bypass data bounds or change records without emitting revisions. Export/import uses a versioned JSON envelope `{formatVersion:1,source,namespace,collections}` without credentials. Namespace erasure and restore-epoch rotation are explicit owner actions, not ordinary app permissions.

- [x] Add browser tests for seeing documents from the todo namespace; valid JSON edit; rejected non-object JSON; stale-edit conflict with draft preservation; revoke-one/all; and an unauthenticated/app-token attempt on every owner endpoint.
- [x] Implement app/session lists and collection/document views, with visible grant scopes, revision, last update, size, and connection state. Render a basic accessible JSON editor; escape every field and disallow untrusted HTML/assets. Test small/mobile viewports and keyboard navigation.
- [x] Implement consistent snapshot export and validate-before-import preview. Apply imports in bounded atomic batches using create-only or explicit CAS semantics; never overwrite merely because IDs match. Show progress and conflicts if an import cannot finish. Test export under concurrent edits, round-trip into a fresh namespace, malformed envelope, oversized content, and deliberate ID collisions.
- [x] Implement precise confirmation for document deletion and namespace erasure. Erasure revokes only that namespace's grants, advances its `namespaceEpoch`, and invalidates its outstanding snapshots/receipts/cursors. Test that retries queued before erasure cannot restore deleted data and another namespace continues normally.
- [x] Provide an owner restore-epoch rotation action and operations instructions requiring session revocation after rolling back a pier backup. Test old clients/cursors being rejected after rotation. Explain that ordinary deletion does not erase historic events/backups.
- [x] Bundle assets into the desk deterministically, add restrictive response headers, and verify no external requests or sensitive data in logs/exports.
- [x] Run `npm --prefix web run typecheck`, `npm --prefix web run build`, `npm --prefix web run test:e2e -- management.spec.ts`, and `python3 scripts/package_desk.py --verify-install`. Inspect rendered desktop/mobile screenshots and actual interactions; fix clipping, focus, contrast, and error states.

**Exit:** the owner can manage the app and its actual stored data without a developer-operated service.

## Task 6: Swift SDK and native todo consumer

**Files:** all `sdk/swift/Sources/UrbitConnect` implementations and native tests; `examples/ios-todo` project and tests; SDK usage section in `README.md`.

**Interfaces:** implement Task 2's public actor unchanged. Internally, `HTTPTransport` preserves pinned issuer/instance/epoch, `TokenStore` isolates credentials by account/client, `LocalStore` atomically persists confirmed state/outbox/cursor, and `SyncEngine` exposes the state stream. The app's `TodoStore` maps `TodoList(schemaVersion,title,tasks)` to generic documents; it cannot reach internal auth or HTTP objects.

- [x] Write native tests `testRejectsCrossOriginRedirectAndIssuerChange`, `testStateAndPKCEBinding`, `testTokenStoreSeparatesAccounts`, and `testRevokedRefreshCannotResumeSync`. Implement the system authorization presenter, fresh verifier/state generation, code exchange, session refresh serialization, and private Keychain storage. Keep owner browser cookies outside URLSession.
- [x] Write SQLite tests `testOutboxSurvivesReopen`, `testCursorAndDocumentsCommitTogether`, `testExactRequestBytesSurviveRetry`, and `testAccountSwitchDoesNotMergeCaches`. Implement local persistence and OS file protection/backup exclusion with explicit migration versioning.
- [x] Write sync tests `testLostSuccessResponseCommitsOnce`, `testEditWhileWriteInFlightPreservesOverlay`, `testConflictPreservesBothVersions`, `testRemoteDeleteDoesNotResurrect`, `testGapResnapshotsWithoutDroppingDraft`, `testExpiredSnapshotRestarts`, `testMutationOlderThan30DaysNeedsReview`, `testRestoreEpochRequiresReauthorization`, `testPermanentRejectionKeepsDraftWithoutRetryLoop`, and `testRevocationRetainsRecoverableUnsentDraft`. Include cancellation and foreground/background transitions.
- [x] Implement snapshot → delta → outbox synchronization, bounded retry/backoff, status publication, conflict resolution, cache cleanup on revocation, and session disconnect. Keep the same request bytes after an ambiguous send; after ambiguous refresh, reauthorize instead of looping. Never mark queued writes Saved before acknowledgement.
- [x] Create the SwiftUI app importing only the public package. Implement pairing, system consent, list/task CRUD, pending/offline/revoked/conflict states, and explicit disconnect. Add `testUnsupportedTodoSchemaRemainsVisible` and `testDuplicateTaskIDsRejected`; data the app cannot decode must remain intact on the ship and in the generic SDK.
- [x] Add native UI tests for approval, denial, cancellation, list creation, task completion, editing, deletion, and conflict recovery against the real isolated ship. Use test credentials through private test harness storage, never launch arguments or captured logs. Tests should drive the real authentication browser; mocks remain confined to unit tests.
- [x] Run `swift test --package-path sdk/swift`, `python3 scripts/ios_test.py --suite unit`, and `python3 scripts/ios_test.py --suite ui`. Build/test via the exact generated Xcode scheme and captured simulator destination; log the underlying command and test counts. Resolve Swift concurrency diagnostics in Swift 6 mode.
- [x] Inspect small and large iPhone layouts, light/dark appearance, large Dynamic Type, VoiceOver labels, keyboard behavior, auth presentation, empty lists, long text, offline recovery, and conflicts. Capture non-sensitive screenshots of the working app and ship interface.

**Exit:** another Swift app can consume the package using its configuration and JSON documents; the todo app works through that package alone.

## Task 7: Complete workflow, fault testing, and delivery

**Files:** `tests/acceptance/prototype-checklist.md`, integration suites, `scripts/check.py`, `README.md`, `docs/{development,security,operations}.md`. Store generated acceptance evidence under ignored `artifacts/acceptance/<run-id>/`.

**Interfaces:** `python3 scripts/check.py --all` executes applicable Hoon, protocol, HTTP integration, web build/browser, native package, and iOS tests in dependency order; nonzero or skipped required suites fail the result. The acceptance checklist records human/UI evidence that automation cannot establish reliably.

- [x] Start from a new isolated pier and a fresh app installation using only the documented setup. Install the packaged desk, pair via HTTPS, approve, create **Personal / Buy milk**, and verify the task appears in the ship manager. Modify the title on the ship and observe it in iOS.
- [x] Repeat after app termination, clean ship restart, isolated abrupt process termination after acknowledged save, and desk upgrade. Verify authoritative state and idempotency receipts rather than only screenshots.
- [x] Interrupt connectivity before send, after commit/before response, during refresh, and during snapshot pagination. Preserve pending edits through app termination. Restore connectivity and prove no duplicate tasks, skipped revisions, silent conflict loss, or unsafe token reuse.
- [x] Connect two independent clients and two sessions of the todo client. Verify namespace isolation; revoke one session and then all app grants while reads/polls/refreshes are active. Show owner data remains available and another app continues working. Confirm unsupported private routes do not leak data.
- [x] Exercise journal truncation, snapshot expiry, namespace erasure, instance replacement, explicit restore-epoch rotation, and owner edits to invalid todo JSON. Verify clear recovery states and preserved user drafts.
- [x] Run bounded load at 100, 500, and 1,000 documents subject to payload quotas; exercise maximum batch size and oversize/rate-limit rejection. Measure read/write/sync latency, memory, and event-log growth. Prototype target on the recorded local environment: p95 ordinary reads/writes under 1 second, remote edit visible in a foreground app within 2 seconds on a healthy connection, and successful reconnect of 1,000 small documents within 10 seconds. Report actual hardware and distributions; do not turn these into network-wide performance promises. Investigate failures before accepting limits or changing targets.
- [x] Run `python3 scripts/check.py --all` on the final files and inspect every suite's case count and skip list. Complete A1–A12 in the design's acceptance matrix, including rendered owner/native UI and accessibility interactions. Add secrets/log scanning of the produced evidence and export artifacts.
- [x] Write a self-contained quickstart for a clean checkout, explicit trust/identity limitations, SDK usage, storage bounds, migrations, backup/restore epoch handling, and how to revoke an app. Package the desk and locally buildable sample. Do not publish externally.
- [x] Stop owned test processes and remove test certificate trust from the disposable environments; retain only intentionally named reproducible fixtures and evidence. Never delete an arbitrary pier or user simulator.

**Exit:** deliver source, reusable Swift package, installable desk artifact, native sample, reproducible setup, and an acceptance report. Any unexecuted required native/runtime/security behavior keeps the prototype incomplete. Report Simulator-only status plainly; before a physical-device pilot, provision a signed build and a user-approved reachable HTTPS test ship and repeat authentication/sync/revocation on the device.

## Execution completion — 2026-10-12

All seven tasks are complete in the agreed local Simulator scope. Checked items refer to the delivered behavior and executed equivalent checks; the initial file/test names were planning targets. Hoon libraries use flat `connect-*.hoon` names; the SQLite/synchronization implementation follows the inspected Swift package layout. Private runners wrap browser/native commands to prevent credential-bearing diagnostics from being printed. Final verified evidence lives in `artifacts/acceptance/`, with raw run IDs under private `.work/`.

Document payload depth remains16; wire/persistence/export envelopes have a separate bounded depth24 to preserve valid document round trips. This and other implementation rulings are recorded in [the ledger](../../implementation-progress.md). No test-only grant adapter ships in the desk. No Git history was created.

The final combined run passed210 cases; fresh setup, fresh-package installation, byte-identical packaging, reviewed screenshots and cleanup also passed. See [the acceptance report](../../../artifacts/acceptance/report.md) and [A1–A12 mapping](../../../tests/acceptance/prototype-checklist.md) for concrete proof and scope limits.

## Plan self-review and execution handoff

- Scope follows the user-selected SDK/desk architecture and ship-readable data decision.
- A1–A12 map to concrete tasks and checks; no task substitutes unit tests for the complete user flow.
- Implementation order establishes contracts, then storage, authorization, management, and native consumption before final acceptance.
- First-prototype limits are explicit: trusted endpoint pairing, generic documents, native Swift SDK, Simulator demonstration, no federated identity assertion or host-blind encryption.
- Do not start implementation from a planning-only request. When the user requests execution, use this plan sequentially unless they choose another method. Ask only for concrete unresolved authority such as using a particular live ship, buying/claiming a domain, or signing/publishing through their developer account.
