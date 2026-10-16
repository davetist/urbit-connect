> Historical plan/specification. Its product quotas and mandatory qualification gates were superseded on 2026-10-16; see [current policy](../../current-readiness.md) and [retained controls](../../capacity.md). It is not a current acceptance contract.

# %connect Reliability Alpha Product Brief

**Status:** revised 2026-10-13 to match the user's simpler scope: approval stays on the ship; no companion app; TestFlight comes later. This replaces the earlier public iOS launch and metadata-service scope. This document authorizes planning, not implementation, purchases or publication.

## Product outcome

Make the existing `%connect` desk, Swift SDK and Todo prototype dependable enough for other ship owners and developers to install, evaluate and integrate. Keep the demonstrated flow:

1. The owner registers a known app in the ship's manager using the developer's documented app ID and callback.
2. In that app, enter the ship address once and tap **Connect with Urbit**.
3. The system browser opens the ship's own login and consent pages. The owner approves that app's permissions on the ship.
4. Return to the app. Its SDK remembers the connection, saves locally when offline and synchronizes directly with the ship.
5. Open the ship's manager to inspect/export data, see sessions and revoke access.

A new grant always requires explicit ship-hosted approval, including reauthorization after revocation or loss of a refresh response. An existing valid session reconnects without asking for the ship address again. Entering an address once per application is acceptable for this alpha.

## Release boundary

The longer-term goal of open access remains: no invitation or %connect staff approval is required to install the released desk or use the released SDK. Registration is an owner-controlled action on each ship, with clear instructions, not a central enrollment service.

The immediate native deliverable is **Todo source plus a reproducible Simulator demo**, not a publicly downloadable iPhone app. A Mac/Xcode is needed to run that demo. This is a narrower milestone than the earlier public native-app launch; it must not be advertised as consumer iOS distribution.

Simulator development does not require paid Apple membership. A free Apple Account can support personal-device development with restrictions, including seven-day provisioning profiles. Physical-device qualification is a separate follow-up and is not inferred from Simulator results. TestFlight/App Store distribution needs an enrolled publisher and is deferred. [Apple account guidance](https://developer.apple.com/help/account/basics/about-your-developer-account), [Apple distribution requirements](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-app-distribution).

## Included and deferred

| Included in this alpha | Deferred |
|---|---|
| Ship-hosted login, consent, app/session management and revocation | Connect companion app, native approval broker and automatic cross-app ship discovery |
| Exact registered custom-scheme callbacks, PKCE, state and scoped sessions | Claimed HTTPS callbacks and verified publisher/binary identity |
| Generic JSON CRUD, explicit conflicts, durable offline outbox and foreground catch-up | Arbitrary queries/indexes, files, collaboration/CRDTs and background push |
| Reliable restarts/updates, bounded resources, restore fencing and draft recovery | New database features or larger default limits |
| Versioned Swift SDK, integration guide and one independent consumer exercise | Other language/platform SDKs and an app marketplace |
| Todo source, Simulator setup, clear pending/saved/offline errors and monochrome UI | Paid signing, physical-phone release claims, TestFlight and App Store delivery |
| Installation/update on one documented real-ship host profile; reproducible releases | A broad hosting matrix, automatic ship provisioning and a hosted relay |
| Sanitized local diagnostics, focused independent review and practical support docs | Public publisher registry/verifier, central service infrastructure and its operations |

The reference host target is Linux ARM64 on a Pi-class machine, qualified on a disposable or explicitly authorized real test ship with valid HTTPS. Record the exact tested runtime/kernel/hardware. Do not claim every host/provider works. Keep the current Mac/fake-ship fixture for development; it is not the evidence for real-ship support. Public docs can live with the repository; a new website/service is unnecessary.

## Existing foundation and concrete gaps

The prototype already implements generic Gall storage, system-browser authorization, scoped sessions, durable documents/receipts, snapshots and polling, a native SQLite cache/outbox, explicit conflicts, an owner manager and Todo. The recorded baseline has 210 passing cases and two Simulator layouts; the later monochrome update has separate visual/build evidence. Requalify the final sources rather than treating that historical count as current release evidence.

Priorities from the inspected source and recorded demo are:

- A desk reload during native polling caused a fail-closed reconnect. Reproduce it and distinguish temporary service failure from invalid credentials/protocol data.
- A restore generation increments from restored state; repeated restoration of the same backup may reuse it. Reproduce and replace that assumption with a fresh generation and a safe restore procedure.
- The local outbox needs explicit capacity/low-storage behavior that preserves unsent edits.
- Pairing errors need to explain the expected ship address. The manager needs clearer connection/refresh state and app/session lifecycle controls.
- Tooling assumes fixed ports, dedicated Simulators and one local fixture. A second source directory alone does not isolate tests from the active demo.
- The Swift package is a local dependency; release provenance/licensing, documented installation and reproducibility need completion. Landscape provenance and the “Unlicensed prototype” docket must be resolved before distribution.

## Authority, identity and privacy

The ship remains the authorization authority and authoritative data store. Its runtime, installed code, host/operator and TLS terminator are trusted; documents are ship-readable. The consuming native app can read its granted data and could copy it elsewhere. Do not promise host-blind E2EE or protection from a malicious consuming app.

For this scope, a client ID and app label are public, unverified identifiers. A manually entered callback is not proof of publisher ownership. Keep exact callback matching, PKCE S256, random state, single-use codes, rotating refresh tokens, CSRF defenses and server-selected namespaces/scopes. Do not add automatic consent based only on a previously seen client ID.

Custom schemes can collide. PKCE protects a legitimate flow's intercepted code, but does not prove which native binary initiated a separate request. The alpha is for known, owner-registered applications and must state that limit; it does not provide verified publisher identity. These distinctions follow the native OAuth guidance on public clients and client impersonation. [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html#section-8.6).

Registering an app is separate from approving a session. Only the authenticated owner changes registration/permissions. Unauthenticated requests cannot create permanent app slots. Removing and re-registering the same public app ID must allocate a fresh local namespace and must not revive old grants. Owner codes/cookies never enter the SDK or Todo network configuration. No publisher URL is fetched to verify an app in this alpha.

The account remains a paired HTTPS issuer and persistent instance ID. The displayed ship name is that endpoint's assertion, not independently verified global Urbit identity. A changed issuer/instance or restore generation requires explicit reconciliation. Logical deletion does not erase historical pier records or backups.

## Data and compatibility contract

Retain the existing conservative limits: 16 KiB document data, 256 KiB requests, 32 operations per batch, 1,000 documents/4 MiB per namespace, 16 MiB total live payload, eight registered clients, 32 sessions, 1,024 journal batches/1 MiB, four concurrent snapshots with 60-second lifetime and 30-day receipts/tombstones. Live payload size is not physical pier disk usage.

Add a local bound of 1,000 pending mutations or 16 MiB of encoded pending requests per account, whichever comes first. Rejection leaves the current edit visible; already queued drafts are never silently evicted. Measure cache/WAL growth and handle disk exhaustion explicitly. Todo keeps its existing list-document schema and explains the 16 KiB limit without losing the edit.

The SDK distinguishes a locally queued write from ship acknowledgement. Preserve exact mutation IDs/bytes over uncertain retries, surface conflicts, and reject unsupported versions before mutation. Use protocol 1 only where compatibility fixtures prove the change additive. The Swift package retains its intended iOS 18+ deployment floor; report compiled targets and tested Simulator runtime versions separately. Do not claim physical-iPhone or production macOS qualification.

## Acceptance and release decisions

Completion requires the existing applicable automated suites plus new reload, retry, storage, restore, registration and conflict regressions; demonstrated end-to-end Todo/ship-manager interaction on both Simulator layouts; real-ship install/update on the reference host; a 6-hour bounded workload soak; a focused independent auth/storage review; and one developer integrating a distinct schema without copying TodoStore. A short seven-day practical trial confirms normal daily use and an in-place update.

The plan supplies measurable gates and commands. TestFlight review, a companion app, verified public publisher enrollment and physical-phone release testing are explicitly outside this milestone, not skipped requirements being counted as passed. A later public native release must bring back its own distribution, identity and device-qualification gates.

Keep black/white/gray UI, accessible status words, readable errors and clear pending/saved states. The only remaining external ownership decisions for this release are source/license, distribution identity/target, the chosen real test host/ship and a maintenance/support contact. An Apple team or registry hosting account is not a prerequisite for this scope.

## Inputs and execution

[Prototype design](2026-10-12-connect-design.md), [protocol](../../protocol.md), [security model](../../security.md), [operations](../../operations.md), [development checks](../../development.md), [baseline acceptance](../../../artifacts/acceptance/report.md), [palette evidence](../../../artifacts/palette/report.md), [Landscape notice](../../../third_party/landscape/NOTICE.md).

[Implementation and verification plan](../plans/2026-10-13-connect-alpha-product.md).
