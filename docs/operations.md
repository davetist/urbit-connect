# Installation, backups and recovery

## Desk artifact

`python3 scripts/package_desk.py --package-only` produces `dist/connect-0.2.0.tgz` and its SHA-256 sidecar. It packages source without starting a ship or executing tests. The archive contains the desk and authentic upstream notices. Its hashes establish artifact integrity, not a qualification verdict. Publication metadata is recorded in `release/ownership.json`.

For a real test ship, first confirm identity, desk ownership and Kelvin compatibility with `desk/sys.kelvin` (408). Choose an explicitly authorized, dedicated test ship; documentation does not authorize changes to an existing deployment. The source workflow is `|new-desk %connect`, `|mount %connect`, copy the verified desk into its mount, `|commit %connect`, then `|install our %connect`. Refuse an unrelated existing desk. Wait for an actual protocol JSON response and the bundled UI after the agent boots; an empty HTTP 200 is not installation proof. See [install](install.md) and [update](update.md).

Serve the ship through a reachable HTTPS endpoint with a valid certificate. Open `/apps/connect/`, log in as the local ship owner, and set up Connect for that exact origin. Register the app ID and exact redirect URI. The included iOS example uses `connect-todo-prototype` and `org.example.urbitconnect.todo:/oauth/callback`. Installing its SDK does not itself grant access: every new connection still requires owner approval.

The iOS Simulator uses the Mac’s localhost. A physical iPhone cannot use that loopback endpoint. A device pilot requires an explicitly chosen reachable HTTPS test ship and an appropriately signed app; no such deployment/signing is included in the local prototype.

## Daily management

The manager shows each app’s namespace, live documents and sessions. Edit JSON with the displayed revision; a stale edit preserves its draft and reports a conflict. The app can encounter unsupported JSON: inspect it in the manager instead of expecting the todo sample to rewrite it.

Use **Manage access** to revoke one session or all app sessions. Revoking keeps documents. **Erase app data** requires the exact namespace and removes its live data while revoking access and advancing its namespace epoch. Other namespaces are unaffected. It does not erase historical events or backups.

Export reads an immutable snapshot, paginated with a renewable 60-second inactivity lease. Import validates a versioned envelope first and applies bounded batches. Create-only mode reports collisions; explicit replacement captures current revisions during preview. Changes after preview still cause CAS conflicts. A multi-batch import can finish partially; the UI reports progress and requires a new preview after failure. Retain the source export until the result is checked.

## Content recovery and failed updates

Export documents through Connect when you need a portable content copy. The export does not contain credentials, sessions, grants or the event log. On a new installation, import the documents and have each client authorize again. A continuously running ship must not be rolled back to an older pier snapshot.

For a failed desk update, preserve current ship state and device drafts while diagnosing the exact failure. Repair the desk with compatible source, then verify grants, documents, receipts and catch-up before resuming writes. If the issuer or persistent instance changes during a separate new installation, clients must pair as a separate account.

An ordinary restart or desk reload preserves the instance, records and receipts. Version-0 state migration preserves the earlier instance identity; version-1 state preserves the durable store and clears transient snapshots/polls on load. Do not overwrite live state to force a failed migration.

## Removing an installation

`|uninstall %connect` stops the desk, but it does not remove Connect's direct HTTP bindings at `/connect` and `/apps/connect`. Eyre only accepts a disconnect from the Gall duct that created a binding. If that agent is nuked first, the binding can remain after its state and desk files are gone. This was observed on a separate 408k receiver during the stable release check. Version 0.2.0 does not provide a complete uninstall procedure; do not nuke a document-bearing Connect agent as routine cleanup. Preserve its data and wait for a supported route-retirement procedure before removing it.

## Test environment cleanup

The development harness stores owner credentials and TLS keys privately under `.work/`, which is ignored. `scripts/cleanup.py` stops only its owned subprocesses and removes the test CA from the dedicated Simulator/profile. It retains piers and diagnostic results for reproducibility. Never upload raw `.work/` or XCTest result bundles: UI typing logs can include the disposable owner code. Share only the sanitized acceptance report and reviewed screenshots.

The former soak service and command are retired. Historical reports and source copies remain under `artifacts/alpha/` and `tests/historical/retired-policy/`. Their recorded duration, failures and source identities are preserved; there is no required new timed run.
