# %connect Reliability Alpha Implementation Plan

**Private qualification update, 2026-10-14:** The owner explicitly removed source owner and maintenance/security contact fields as blockers for the private alpha. They remain deferred publication metadata. Keep all technical, independent-human and seven-day trial gates. Following the memory investigation and bounded diagnostic, the owner authorized a fresh soak of 6 actual hours; preserve earlier failed runs and never credit their elapsed time to the new run.
> **For agentic workers:** This is a plan update, not authorization to implement or publish. When execution is requested, use `superpowers:executing-plans` task by task; delegate only if the user authorizes that workflow. Checkboxes are future work. Never run the mutating prototype harness against the active demo or a personal ship.

**Goal:** Make the existing desk, Swift SDK and Todo prototype reliable, with all login and approval remaining on the ship. Deliver a reproducible source/Simulator experience and an installable desk on one qualified real-ship host profile.

**Architecture:** One authoritative Gall agent, a ship-hosted owner manager/consent page, direct HTTPS transport and a Swift SDK with SQLite cache/outbox inside Todo. Each app remembers its own paired ship. Owner-controlled app registration stays local to the ship. No companion app, authorization broker, publisher-verification service or central data backend is introduced.

**Tech stack:** Hoon/Gall/Eyre/Clay; TypeScript/Vite; Swift 6/SwiftUI/AuthenticationServices/Keychain/SQLite; existing Python/Playwright/Xcode Simulator tooling; a maintained HTTPS ingress on the reference real host.

**Spec:** [Revised product brief](../specs/2026-10-13-connect-alpha-product-brief.md). Retain the [prototype contract](../specs/2026-10-12-connect-design.md) wherever this revision does not replace it.

**Revision:** 2026-10-13. Supersedes the earlier 17-task public native-release plan. TestFlight, paid signing, physical-phone release qualification, claimed HTTPS callbacks, the metadata registry and public-service operations are removed from this milestone. The long-term open-access goal remains; the native deliverable here requires source/Xcode/Simulator and is not a consumer iPhone download.

## 1. Scope and definition of success

Keep the working flow: owner registers a known app on the ship → user enters a ship address once in Todo → the system browser opens that ship's login/consent → user approves on the ship → SDK retains its own scoped session → Todo synchronizes directly with the ship → owner inspects or revokes through the ship manager.

| Area | This alpha must deliver | Later milestone |
|---|---|---|
| Approval | Existing system-browser, ship-hosted login and explicit consent | Companion app or cross-app ship discovery, if wanted |
| App registration | Documented owner registration; unverified names/IDs clearly labeled | Publisher verification and claimed HTTPS redirects |
| Data | Reliable CRUD, outbox, conflicts, quotas and recovery | Broader database features and larger limits |
| SDK/Todo | Reproducible Simulator flow and one independent SDK integration | Physical-device qualification and public native distribution |
| Desk installation | One tested Linux ARM64/Pi-class real-ship profile over valid HTTPS | Wider hosts/providers and automatic provisioning |
| Delivery | Desk artifact, versioned Swift package/source, docs and release evidence | TestFlight/App Store and public-service infrastructure |

There is no %connect staff enrollment gate. Owners can register known apps themselves using developer-supplied instructions. The absence of publisher verification is explicit; this release is not a promise that a copied native app identity can be detected. Do not describe the source/Simulator demo as a substitute for a publicly installable iPhone app.

The baseline acceptance report records 210 passing cases before the palette follow-up. Re-run the final sources in safe fixtures. Known priorities are the observed live-reload reconnect, repeated-backup generation reuse concern, missing outbox capacity handling, confusing origin input and release/tooling assumptions. A source-level concern is not a reproduced vulnerability until its regression demonstrates it.

## 2. Global constraints

- Keep approval, permission changes and revocation on the ship. The SDK/Todo never receive the owner code or browser cookie. An app remembers its own connection; it cannot read another app's saved pairing.
- Preserve TLS validation, exact registered callbacks, PKCE S256, random state, single-use codes, refresh rotation, CSRF protection and server-enforced namespaces/scopes. New authorization always shows consent; a remembered client ID never silently approves a new grant.
- Keep the current owner-registered custom-scheme callback for this scope. Do not add a client secret as a substitute for native publisher authentication. Claim only the registration/consent protections actually tested. [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252.html#section-8.6).
- Temporary service failure must not erase valid credentials or confirmed data. Lost refresh responses still require safe reauthorization; do not replay consumed refresh tokens to hide that condition.
- A queued edit is not a ship-acknowledged save. Preserve mutation IDs/bytes across uncertain retries, unsent drafts across supported upgrades, and explicit reconciliation after conflicts or restored state.
- Retain all server bounds in the brief, including 16 KiB/document, 1,000 documents/4 MiB per namespace, eight app registrations and 32 sessions. Add the local limit of 1,000 pending mutations or 16 MiB encoded requests/account. Never silently evict unsent work.
- Use ship-readable data and direct app-to-ship transport. The host, runtime, installed ship code, TLS terminator and consuming app remain trusted as described in the brief; do not claim host-blind encryption or verified global ship identity.
- Keep iOS 18+ as the intended deployment floor; record which Simulator runtimes actually pass. Compile-target checks do not establish physical-device support. This milestone needs no paid Apple membership or TestFlight.
- Preserve black/white/gray styling and accessible status text. Avoid new database schemas, a companion app, new services or a marketing website to finish this work.
- Use isolated fixtures and explicitly authorized real targets. Planning does not authorize Git creation, publication, purchases, Apple enrollment, production changes or messages to testers.

## 3. Review focus

1. **Reload during polling, mutation or refresh:** distinguish service interruption from rejected credentials, resume without duplicate effects, and preserve safe refresh ambiguity behavior. T03/T09.
2. **Restore the same old backup twice:** old tokens, cursors and queued creates must not regain validity through generation reuse. T05/T09.
3. **Terminate an offline app or exhaust its storage:** the durable outbox and visible edit remain consistent; no false “Saved” status or dropped draft. T04/T07/T09.
4. **Revoke/remove an app while it is retrying:** pending consent, sessions and old namespaces stay invalid; re-registration does not resurrect them. T02/T06/T09.
5. **Install or update with the wrong origin/version/fixture:** reject unsafe targets and incompatible state; explain recovery without weakening TLS or touching the active demo. T01/T02/T08/T09.

## 4. Milestones and dependencies

| Milestone | Deliverable | Tasks |
|---|---|---|
| M0 Reproducible foundation | Safe test targets, current baseline and frozen existing auth contract | T01–T02 |
| M1 Reliable core | Restart/retry, offline storage and restore/migration behavior | T03–T05 |
| M2 Usable prototype | Owner manager, clear pairing and documented SDK/Todo | T06–T07 |
| M3 Real installation and qualification | Tested install/update, combined failure/security evidence | T08–T09 |
| M4 Reliability alpha | Independent trial, documentation and authorized artifact release | T10 |

T01 precedes T02. T03 and T04 use T02; T05 follows T03. T06 consumes T02/T04 and T07 integrates T03–T06. T08 can prepare host instructions early but completes with T05/T07. T09 qualifies T01–T08; T10 follows T09. Task IDs below replace the old numbering; all dependencies refer to these ten work packages.

## 5. Implementation work packages

All paths are relative to `connect/`. “Create” denotes a proposed artifact. For each behavior change, add a meaningful failing regression, implement the fix, run its targeted tests and then the combined qualification. Existing paths may need small focused helpers; do not reorganize unrelated code. Commits/branches are not assumed by this plan.

### T01 Make baseline verification isolated and reproducible

**Owner / effort:** tooling/release engineer; 3–5 engineer-days. **Depends:** none.

**Files:** `toolchain.json`, `scripts/setup.py`, `scripts/check.py`, `scripts/dev_ship.py`, native/browser fixture helpers, `.gitignore`, `third_party/landscape/NOTICE.md`; create `scripts/release_check.py`, `release/manifest.schema.json`, release/licensing notes and an authorized CI workflow when a repository exists.

**Interface:** an owned fixture configuration binds every pier path, listener port, TLS material and Simulator target. The runner refuses targets it does not own. A release manifest binds desk/web/SDK/Todo source hashes, toolchain versions and sanitized evidence; add the source commit when a repository is authorized.

- [ ] Test that a second source directory cannot silently reuse the active demo's fixed ports or Simulator. Parameterize all consumers before running side by side, or use a separate test Mac/VM. Reject ownership mismatch before any reset, stop, registration or erase.
- [ ] Reproduce setup from pinned dependencies and run `python3 scripts/check.py --all` against those isolated fixtures. Inspect actual nonzero counts and all native/browser evidence; do not reuse the old 210-case report as current proof.
- [ ] Build unsigned desk/web/package outputs twice from clean sources and compare hashes. Exclude piers, credentials, test-control endpoints, raw recordings and signing material from artifacts.
- [ ] Resolve the Landscape provenance/license limitation and select the root license before external release. Document source ownership, contribution and security contact. Local hardening may proceed while these publishing decisions are settled.

**Gate:** isolated setup and the existing baseline are reproducible without touching the user's demo; release inputs are recorded and publication blockers are visible. Licensing must be resolved by T10 before anything is distributed.

### T02 Retain and test ship-hosted authorization

**Owner / effort:** protocol/Swift engineer; 3–5 days. **Depends:** T01.

**Files:** `protocol/v1/openapi.yaml`, shared fixtures, `desk/lib/connect-auth.hoon`, `desk/lib/connect-http.hoon`, `desk/sur/connect.hoon`, `sdk/swift/Sources/UrbitConnect/AuthorizationSession.swift`; create `docs/app-registration.md` and `docs/compatibility.md`.

**Interface:** keep the current registered client ID/custom callback and system-browser presenter. Reuse `GET /connect/v1/info` for issuer/instance/protocol preflight; document version/limit compatibility without requiring a new discovery endpoint. Owner registration creates a local app record; granting a session remains a separate authenticated consent action.

- [ ] Add fixtures for exact callback matching, PKCE/state mismatch, code replay/expiry, cancellation, denial, wrong issuer/instance, missing desk and unsupported versions. Reject incompatible state before mutation; use a new protocol major only if required by breaking semantics.
- [ ] Verify owner credentials remain exclusively in the ship's browser authentication boundary. A previously approved client ID must still show consent for a fresh grant. Keep current private browser-session behavior unless a separately reviewed change is needed.
- [ ] Document and validate the owner registration fields and sample configuration. Treat names and IDs as unverified labels, reject registration changes from unauthenticated clients, and never fetch a supplied publisher URL. No staff enrollment or metadata service is involved.
- [ ] Test callback substitution, cross-client token use, scope escalation, disabled clients, CSRF and malformed/oversized requests. Test duplicate custom-scheme handling without claiming it proves native publisher identity; record that active client impersonation is outside this limited identity assurance.
- [ ] Publish the supported desk/SDK pair table and exact reauthorization behavior. Retain explicit origin/instance pinning and fail-closed handling of inconsistent successful protocol responses.

**Gate:** Todo opens the actual ship consent page, approve/deny/cancel behave correctly, and all authority checks pass. A copied name/ID alone is not a credential, but the release does not promise authenticated native publisher identity.

### T03 Recover from restarts, reloads and uncertain responses

**Owner / effort:** Hoon/Swift engineer; 4–7 days. **Depends:** T02.

**Files:** `desk/app/connect.hoon`, `desk/lib/connect-http.hoon`, Swift `HTTPTransport.swift`, `ConnectClient.swift`, `SyncEngine.swift`; lifecycle/sync HTTP and native tests.

**Interface:** distinguish retryable availability errors such as bounded HTTP 503/`server_restarting` from an invalid successful response or explicit authorization rejection. Preserve exact mutation bytes/IDs until the outcome is known.

- [ ] Reproduce the observed palette-update reconnect with a pending native poll; record sanitized status/content type/error classification to identify the actual cause.
- [ ] Cover reload/restart before and after mutation commit, during long poll/snapshot and around refresh. Complete or cancel pending HTTP work deterministically; add capped retry/backoff with jitter and foreground recovery.
- [ ] Run 100 desk reload cycles and 1,000 dropped-mutation-response retries on disposable fixtures. Assert no lost acknowledged records, no duplicate effects, no premature credential clearing and normal recovery after availability returns.
- [ ] Test lost refresh responses separately: preserve drafts and explain required reauthorization. A successful retry policy must not accept malformed protocol responses or consumed refresh tokens.

**Gate:** the observed failure has a passing regression; ordinary compatible upgrades/restarts retain sessions and recover synchronization. Only documented genuinely ambiguous refresh/identity conditions require reauthorization.

### T04 Make offline writes, conflicts and resource limits dependable

**Owner / effort:** storage/SDK engineer; 4–7 days. **Depends:** T02.

**Files:** `desk/lib/connect-store.hoon`, `connect-http.hoon`, `connect-auth.hoon`; Swift `LocalStore.swift`, `SyncEngine.swift`, `ConnectClient.swift`, `Models.swift`; HTTP limits/sync and Swift storage tests; create `docs/capacity.md`.

**Interface:** atomically enqueue mutation payload and local state. Return a typed local capacity error before accepting a new mutation when 1,000 pending mutations or 16 MiB encoded pending requests/account would be exceeded. Keep server limits unchanged.

- [ ] Test offline enqueue → process termination → reopen → synchronization, dropped acknowledgements, out-of-order completion and concurrent edits from a second client/manager. Pin conflict outcomes and ensure UI resolution cannot overwrite newer data silently.
- [ ] Test exact count/byte boundaries, SQLite disk-full faults, interrupted commits, WAL growth and quota release after acknowledged sync. Preserve both queued drafts and a rejected editable input. These are Simulator/fault-injection results, not physical-device storage certification.
- [ ] Measure cache/WAL and retained-account usage, set documented finite budgets and evict only recoverable confirmed caches. Never delete unsent work to meet a budget.
- [ ] Exercise server request/document/batch/session/snapshot bounds, rate limits and per-app fairness. Bound ingress body/time/connection work before expensive processing; a saturating client must not starve another granted app.
- [ ] Keep receipts/tombstones for their promised retention, test exact replay responses, and report live JSON payload separately from metadata, RSS and physical pier/event-log growth.

**Gate:** acknowledged writes remain correct, uncertain retries have one effect, conflicts are explicit and all capacity failures preserve existing data and drafts. T09 confirms behavior under sustained load.

### T05 Prove backup restoration and compatible migrations

**Owner / effort:** storage/operations engineer; 4–7 days. **Depends:** T02–T03.

**Files:** `desk/lib/connect-state.hoon`, `connect-http.hoon`, `desk/sur/connect.hoon`, Swift `LocalStore.swift`/`ConnectClient.swift`; create `scripts/restore_rehearsal.py`, restore/migration fixtures; update `docs/operations.md`.

**Interface:** restoring establishes a fresh generation from runtime entropy, within the bounded decimal-string representation if compatible. Treat generations as opaque equality identifiers, never only as a counter contained in a backup.

- [ ] Reproduce restoring the same old backup twice after different intervening timelines. Include old tokens, cursors, receipts and queued creates; none may regain authority through generation reuse.
- [ ] Implement the supported sequence: isolate ingress/network, verify/restore backup, rotate generation and revoke sessions through owner authority, verify old-client rejection, then reopen. Keep clone piers network-isolated so the same real identity is never concurrently active on Ames.
- [ ] Restore actual backup files and compare against their known recovery point. Writes acknowledged after that backup are outside its contents; report that loss window accurately. Do not claim automatic rollback detection without an external trustworthy signal.
- [ ] Test desk state and SQLite schema migrations with pending work, including repeated upgrade attempts. Preserve compatible sessions/data; reject unsupported downgrade without destructively opening a newer database.
- [ ] Make retained drafts readable/exportable before account replacement/removal. Explain that ship backup cannot recover an edit never sent by the phone, and uninstall/device loss can lose local-only drafts.

**Gate:** a second operator completes two isolated restore rehearsals from instructions; old grants/queued writes are blocked and drafts require deliberate reconciliation. In-place supported upgrades preserve state without a restore-style re-pair.

### T06 Finish the ship manager and clarify pairing

**Owner / effort:** web/Swift engineer; 3–5 days. **Depends:** T02, T04.

**Files:** `web/src/main.ts`, `apps.ts`, `consent.ts`, `api.ts`, related manager views; `examples/ios-todo/ConnectTodo/PairingView.swift`, `TodoStore.swift`; browser/native UX regressions; create `docs/quickstart-owner.md`.

**Interface:** reuse existing owner client name/enabled/session/revoke routes. Add safe registration removal with a fresh namespace on re-registration, and a preflight result distinguishing address/network/TLS/desk/version/identity errors.

- [ ] Make first-run setup generic; registering Todo is an explicit sample option. Show a copyable canonical ship address and the exact approved permissions. Explain unverified app names without pretending an ID is publisher proof.
- [ ] Recognize a pasted known manager URL and offer its base origin for confirmation. Reject unknown paths and invalid certificates; never silently chase arbitrary redirects. Remember the confirmed endpoint for subsequent launches of that app.
- [ ] Complete rename, disable/re-enable, session display, revoke-one/all and registration removal using existing server logic. Distinguish revoke-and-keep-data from export/erase/remove. Only the latter frees an app slot after explicit destructive confirmation.
- [ ] Test removal/revocation during polling, retry and pending consent. Re-registration must allocate a fresh namespace and invalidate old grants/approvals; an unchanged public client ID cannot revive deleted authority.
- [ ] Add bounded foreground refresh and clear pending/saved/offline/revoked/conflict states without replacing an editor's draft or selection. Verify monochrome light/dark, keyboard/VoiceOver and Dynamic Type on the supported Simulator layouts.

**Gate:** the owner can register, approve, inspect, export and revoke from the ship; Todo reports recoverable problems in plain language. No native companion or separate approval location appears in the flow.

### T07 Package the SDK and Todo as reproducible developer tools

**Owner / effort:** Swift/developer-experience engineer; 3–5 days. **Depends:** T03–T06.

**Files:** `sdk/swift/Package.swift`, public SDK sources/tests, Todo project/source/tests; create an integration guide and `tests/consumers/swift/`; update `docs/development.md` and protocol examples.

**Interface:** document the existing `connect`, cached reads, `put`/`delete`, `observe`, connection status, conflict resolution, draft recovery and disconnect behavior. An enqueue acknowledgement is distinct from a ship save.

- [ ] Keep Todo as a normal SDK consumer. Preserve its list-document schema, handle the 16 KiB limit before discarding input and show retry/conflict/draft recovery without private SDK hooks.
- [ ] Build/run from a clean Mac checkout through documented Simulator steps with no paid signing or developer-account enrollment. Record compiled minimum target and actual tested runtimes/layouts; do not claim physical-phone support from this evidence.
- [ ] Prepare versioned package/source distribution, resolving the nested Swift package layout through a consumable root package or SDK release repository when publication is authorized. Document the local path workflow until then; no private dependency or credential injection may be required.
- [ ] Exercise SDK foreground/background transitions, cancellation, concurrent connect/disconnect/refresh and simulated storage/Keychain failures. Keep successful app-update migrations separate from destructive test reinstall setup.
- [ ] Have one independent developer create a distinct-schema consumer from the docs, register it through the ship manager and complete authorization/CRUD/conflict/revocation. No SDK fork, copied TodoStore or team-operated enrollment counts. Target first round trip within half a day after the ship/Xcode prerequisites are ready.

**Gate:** another developer can reproduce Todo and integrate the SDK using documented interfaces. Simulator evidence is labeled accurately; physical-device and TestFlight work remain a later gate.

### T08 Qualify one real-ship installation and update path

**Owner / effort:** Urbit/operations engineer; 4–6 days. **Depends:** T01, T05, T07.

**Files:** `desk/desk.docket-0`, `desk/sys.kelvin`, owner-selected publishing metadata, `scripts/package_desk.py`; create `scripts/doctor.py`, `docs/install.md`, `docs/update.md`, `docs/supported-platforms.md` and one reference ingress configuration.

**Interface:** read-only `doctor` reports sanitized endpoint/version/compatibility/space status. Installation/update requires explicit target identity, checks desk ownership/collisions and preserves a verified recovery path.

- [ ] Qualify one Linux ARM64/Pi-class profile using a disposable or explicitly authorized real test ship. Record exact hardware, kernel/runtime versions and disk/RAM requirements. Choose the supported stable runtime at qualification time; do not copy the Mac-specific LMDB workaround into production guidance by default.
- [ ] Document a reachable HTTPS origin with valid OS-trusted certificates, renewal, ingress/body/time limits, proxy trust and admin-interface binding. The Simulator must reach that real ship without globally weakening TLS. Local development certificates remain confined to owned development fixtures.
- [ ] Exercise clean install, already-installed compatible update, missing/wrong desk, partial setup, expired certificate, insufficient space and safe refusal of an unsupported version. Preserve sessions, documents and queued edits over supported updates.
- [ ] Set accurate license/publisher/version and monochrome tile metadata; remove automatic sample seeding. Test self-contained assets with no hidden developer process. Provide a verified archive recovery path and source of authentic release artifacts.
- [ ] Have a second operator follow install/update instructions without a live coaching session. Document a provider refusing custom desks as an unsupported environment, not a working installation. Keep any future distribution channel staged before publishing updates broadly.

**Gate:** real-ship install and update work on the named reference profile, and its prerequisites/limits are reproducible. Native phone distribution and additional host profiles do not block this narrower, honestly labeled result. Urbit desk updates and kernel compatibility must be reflected in the release procedure. [Urbit distribution](https://docs.urbit.org/build-on-urbit/userspace/dist).

### T09 Complete combined reliability and focused security qualification

**Owner / effort:** QA/platform engineer; 5–8 days plus unattended soak and independent reviewer time. **Depends:** T01–T08.

**Files:** existing acceptance/benchmark/native/browser suites; create `tests/acceptance/alpha-matrix.md`, `scripts/qualify_alpha.py`, release-linked sanitized reports and a focused auth/storage review record.

**Interface:** proposed `qualify_alpha.py --release-manifest <file> --targets <isolated-targets.json> --all` binds results to artifacts and owned targets. It rejects missing/zero/skipped required automated cases and incomplete required manual evidence. It is a deliverable, not an existing command.

- [ ] Run every existing applicable suite and new regressions; validate the shipped web bundle and packaged desk, not only source modules. Run mutating suites sequentially and assert ownership before reset/kill/erase.
- [ ] Demonstrate the complete workflow on both Simulator layouts and the real reference ship: ship consent → create/update/delete → manager observation → offline termination/catch-up → conflict → revoke → reauthorize → in-place desk and app update. Use a preserved install for the app-update test, not the runner's normal reinstall path.
- [ ] Test 1,000 documents/4 MiB, eight apps, 32 sessions and four snapshots with mixed sizes/churn. On the reference host, require p95 CRUD <1 second locally; at 100 ms RTT/1% loss require p95 <2 seconds, remote foreground visibility <5 seconds and a 1,000-small-document snapshot plus local install <30 seconds. At 500 ms/5% loss, require safe eventual progress after recovery and accurate pending status.
- [ ] Complete a 6-hour churn/idle soak on the reference host. Require no data loss, duplicated effects, hangs or unbounded retained memory. Compare like-for-like post-cleanup RSS and retained heap to warm baseline with a 15% tolerance; investigate failures. Measure event-log/disk growth per workload rather than expecting historical data to disappear.
- [ ] Exercise generation/receipt/tombstone expiry boundaries using controlled clocks and elapsed-time samples, clock skew, quota exhaustion and compatibility in both upgrade orders. Repeat only affected checks after fixes and then the final combined release check.
- [ ] Obtain a focused independent review of actual auth/storage/HTTP/Gall/SDK sources and regressions: consent, namespace/scope checks, callback/code handling, CSRF, restore fencing, refresh races, malformed input, resource exhaustion and leaks. Fix authority/data-loss findings before release. Record the custom-scheme publisher-identity limitation; do not call this an exhaustive security audit.
- [ ] Verify error reports/logs/exports omit credentials, owner codes, document bodies and task titles using canary strings. Keep diagnostics local and owner-exported; publish only sanitized evidence and a practical bug-report template.

**Gate:** every current-scope acceptance row passes with linked evidence and no unresolved data-integrity/authorization failures. Physical-device testing, claimed HTTPS app identity and TestFlight are outside the declared artifact/platform scope; they are not marked passed or substituted by Simulator checks.

### T10 Run a small practical trial and prepare the reliability release

**Owner / effort:** product/release/support; 2–4 days plus seven elapsed days of practical use. **Depends:** T09.

**Files:** `docs/release-checklist.md`, `docs/support.md`, `docs/known-limitations.md`, `docs/backup-policy.md`, release manifest/notes and updated quickstarts. Public docs may remain in the repository.

- [ ] Have 2–3 owner/developer testers use the source/Simulator flow with their own authorized test setups for seven days, including one desk update and one offline recovery. Record failures; an integrity/authority defect requires a fix and another relevant observation period before release.
- [ ] Require an unfamiliar owner/developer to install/update the desk and an independent developer to reproduce the Todo/SDK flow from docs without author-operated configuration. Start with a supported ship/HTTPS and Xcode ready; list those prerequisites explicitly. Target first Todo save within ten minutes after desk/sample registration and Simulator setup are complete; report setup time separately.
- [ ] Publish the exact supported versions, known app-identity limits, backup recovery-point limits, source/Simulator requirement, external integration example and troubleshooting steps. Keep a named maintainer/security contact and a local diagnostics export; a status-service stack is unnecessary here.
- [ ] Reconcile the release manifest against final tests, license/notices and the packaged artifacts. Once the user authorizes exact targets, publish the desk/source/SDK through the selected channels and test clean retrieval/install. If publication is not authorized, deliver a verified local release bundle and clearly report that distribution is pending.

**Gate:** a reproducible, supportable desk/SDK/source-demo alpha with reviewed evidence and no hidden Apple membership, companion app, registry or staff-enrollment dependency. Local artifact readiness and actual public availability are reported separately.

## 6. Verification commands and release checklist

Run these only after T01 isolates the fixed ports/fixtures/Simulator from the user's demo. Commands below are existing entry points verified from [development instructions](../../development.md); no product tests are run simply to edit this plan.

| Scope | Command / required outcome |
|---|---|
| Full current baseline | `python3 scripts/check.py --all` — all enumerated suites execute with authoritative nonzero counts and no required skips |
| Protocol/auth | `python3 scripts/check.py --suite protocol`, then `--suite hoon`, then `--suite integration` — include all new fixtures/regressions in enumeration |
| Manager | `npm --prefix web run typecheck`, `npm --prefix web test`, `npm --prefix web run build`, `python3 scripts/bundle_web.py`, `python3 scripts/package_desk.py`, then `python3 scripts/check.py --suite web` — verify the current generated assets and relevant new specs |
| SDK/Simulator | `swift test --package-path sdk/swift`, `python3 scripts/ios_test.py --suite all`, `python3 scripts/ios_test.py --suite ui --small` — inspect separate visual/manual and preserved-install upgrade evidence |
| Packaging | `python3 scripts/package_desk.py --verify-install` — actual archive compilation and install in an owned fixture |
| New alpha matrix | T09's `scripts/qualify_alpha.py` command — host/Simulator/fault/soak results plus required operator/reviewer evidence |

| Release gate | Required evidence |
|---|---|
| Isolation/provenance | Active demo untouched; clean build hashes; license/notices resolved before distribution |
| Ship approval | Explicit consent, callback/PKCE/state/code tests, owner-only registration and scope enforcement |
| Update/retry | Observed reload regression fixed; 100 reloads; 1,000 dropped-response retries; preserved-install app upgrade |
| Offline/limits | Durable outbox, conflicts, precise quota edges, injected storage failures, no draft eviction |
| Restore/migration | Same-backup repetition, fresh generation, old grants blocked, two operator rehearsals |
| Installation | Named real Linux ARM64 profile, normal HTTPS, independent install/update |
| Usability/integration | Both Simulator layouts; one distinct SDK consumer; clear ship manager and pairing errors |
| Review/qualification | Final complete suite, 6-hour soak, focused independent review, redacted evidence |
| Practical delivery | Seven-day trial, documented source/Simulator requirements, named maintainer and verified release bundle |

Out of this release contract: signed physical-phone qualification, public TestFlight/App Store delivery, associated-domain publisher identity, companion/broker behavior, central verifier operation and additional host/platform matrices. Reintroduce their tests and provisioning explicitly when that scope is requested; do not count them as passed now.

## 7. Effort and sequencing

The ten tasks total **35–59 engineer-days**. With 20% contingency, allow **42–71 engineer-days**, plus independent reviewer time/fees and external waiting. Indicative elapsed time is **6–10 weeks for two engineers with focused specialist help**, or **10–16 weeks for one engineer**, including qualification and the practical trial. These are human planning estimates, not fixed delivery dates.

| Sequence | Work |
|---|---|
| Foundation | Safe fixtures/current baseline, existing ship auth/compatibility contract |
| Core | Reload/retry, offline/conflicts/limits and restore/migrations |
| Product | Manager/pairing, packaged SDK and reproducible Todo |
| Qualification | Reference real host, final failure/load/security checks, independent integration |
| Delivery | Practical trial, release evidence/docs and separately authorized publication |

The reduction comes from deferring the proposed public service, TestFlight/signing/device release work, broad host qualification and the larger public-consumer launch process. The separately discussed companion app is also excluded. It does not come from waiving data-integrity or authorization checks. Costs are engineering/review, existing Mac/Xcode access, a reference ship/host with HTTPS, build storage and maintenance. No paid Apple membership, new registry hosting or central database is required for this milestone.

## 8. Explicitly deferred work

- **Companion app:** excluded. Approval remains on the ship; each app stores its own paired address.
- **TestFlight/App Store:** later, with an enrolled publisher, paid-program capabilities as needed, signed builds and physical-device qualification. A free Personal Team can be explored for personal development, but its restrictions are not a distribution strategy. [Apple account guidance](https://developer.apple.com/help/account/basics/about-your-developer-account), [distribution requirements](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-app-distribution).
- **Publisher identity/enrollment service:** no registry/verifier, metadata-service API, worker/SSRF infrastructure or associated operating budget in this alpha. If verified public native publishers become a requirement, design and review that separately; owner consent is not proof of publisher identity.
- **Expanded platform/data features:** wider hosts, web/Android/Flutter SDKs, attachments, queries/indexes, sharing, CRDTs, background push, ship provisioning, federated ship identity and host-blind E2EE.

## 9. First execution slice and remaining decisions

Start with T01's safe baseline and T02's existing ship-consent regressions, then reproduce/fix the actual reload issue in T03. Storage/restore and UX work follow the dependency order. Use the current demo as a preserved reference, not a destructive test fixture.

The settled choices are ship-readable data, ship-hosted approval, no companion, Simulator/source Todo and deferred TestFlight. Before external release, the owner still selects the license/source owner, publishing ship/channel, exact real test host/ship and maintenance contact. Local hardening does not need an Apple signing team or central-service account. Do not invent external identities or treat this planning edit as publication/deployment authorization.

## 10. Plan consistency and reporting

Coverage: auth T02; restart T03; data/limits T04; restore T05; owner UX T06; SDK/Todo T07; install T08; combined qualification/review T09; release/support T01/T10. Every review-focus failure has a named test owner. State baseline evidence, proposed changes and newly demonstrated behavior separately. This update modifies only the brief and plan; implementation and runtime verification belong to later execution.
