# Installation, backups and recovery

## Desk artifact

`python3 scripts/package_desk.py --verify-install` produces `dist/connect-0.2.0-alpha.1.tgz` and its SHA-256 sidecar, verifies the file manifest, installs the archive on a fresh owned fake ship, and checks the protocol and bundled UI. The archive contains the desk and authentic upstream notices. It is a local candidate whose private qualification requires the technical evidence in the alpha matrix. Source ownership/contact metadata and publishing authorization are deferred public-distribution prerequisites.

For a real test ship, first confirm identity, desk ownership, a verified stopped-pier backup and Kelvin compatibility with `desk/sys.kelvin` (408). This task authorizes only the separate `connect-dev` test pier on reference-host. The source workflow is `|new-desk %connect`, `|mount %connect`, copy the verified desk into its mount, `|commit %connect`, then `|install our %connect`. Refuse an unrelated existing desk. Wait for an actual protocol JSON response and the bundled UI after the agent boots; an empty HTTP 200 is not installation proof. See [install](install.md) and [update](update.md).

Serve the ship through a reachable HTTPS endpoint with a valid certificate. Open `/apps/connect/`, log in as the local ship owner, and set up Connect for that exact origin. Register the app ID and exact redirect URI. The included iOS example uses `connect-todo-prototype` and `org.example.urbitconnect.todo:/oauth/callback`. Installing its SDK does not itself grant access: every new connection still requires owner approval.

The iOS Simulator uses the Mac’s localhost. A physical iPhone cannot use that loopback endpoint. A device pilot requires an explicitly chosen reachable HTTPS test ship and an appropriately signed app; no such deployment/signing is included in the local prototype.

## Daily management

The manager shows each app’s namespace, live documents and sessions. Edit JSON with the displayed revision; a stale edit preserves its draft and reports a conflict. The app can encounter unsupported JSON: inspect it in the manager instead of expecting the todo sample to rewrite it.

Use **Manage access** to revoke one session or all app sessions. Revoking keeps documents. **Erase app data** requires the exact namespace and removes its live data while revoking access and advancing its namespace epoch. Other namespaces are unaffected. It does not erase historical events or backups.

Export reads an immutable snapshot, paginated with a 60-second lifetime. Import validates a versioned envelope first and applies bounded batches. Create-only mode reports collisions; explicit replacement captures current revisions during preview. Changes after preview still cause CAS conflicts. A multi-batch import can finish partially; the UI reports progress and requires a new preview after failure. Retain the source export until the result is checked.

## Backup restore

Take and restore full pier backups using your established Urbit operator workflow. A document export is portable content, not a complete backup of credentials, sessions, revisions or the event log.

After restoring an older pier, isolate ingress and network/Ames first. Verify the backup files against their recorded hashes and known recovery point. Use private owner access to Connect’s **Restore recovery** action and confirm the instance ID. This creates a fresh opaque generation from runtime entropy and revokes sessions/codes/receipts; it is not a counter recovered from the backup. Verify old tokens, cursors and queued grants are rejected before reopening ingress. Obtain new approval and a fresh snapshot, then deliberately reconcile retained device drafts. Writes acknowledged after the backup are outside its contents, and the ship cannot recover edits never sent by the phone. If the issuer or persistent instance changes, pair as a separate account.

An ordinary restart or desk reload preserves the instance, records and receipts. Version-0 state migration preserves the earlier instance identity; version-1 state preserves the durable store and clears transient snapshots/polls on load. Failed migrations must leave the prior pier backup available; do not overwrite it to force an upgrade.

## Test environment cleanup

The development harness stores owner credentials and TLS keys privately under `.work/`, which is ignored. `scripts/cleanup.py` stops only its owned subprocesses and removes the test CA from the dedicated Simulator/profile. It retains piers and diagnostic results for reproducibility. Never upload raw `.work/` or XCTest result bundles: UI typing logs can include the disposable owner code. Share only the sanitized acceptance report and reviewed screenshots.

The real-host soak is a finite 6-hour run with mixed-size create/update/delete cycles, exact receipt replays, normal HTTPS and a final resource evaluation. A failed run cannot contribute elapsed time to a later run. Preserve its report, start record, worker sources and private state before an explicitly authorized fresh start. Diagnostic replays also do not count toward qualification.

The scalar failure report includes its phase, source file/line/function and the last request's category, method, HTTP status and allowlisted error code when available. It excludes exception text, URLs, bodies, headers and credentials. Keep owner authentication and `soak-state.json` on their existing hosts; export only reviewed scalar evidence. A running report has `passed:false` until 6 actual hours and the final integrity/resource checks succeed. The service has a 7-hour maximum and restart disabled.
