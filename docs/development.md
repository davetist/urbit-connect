# Development and verification

Run all commands from the project directory. `toolchain.json` pins runtime/pill/Caddy hashes and the tested Xcode/Simulator versions. `scripts/requirements.lock` and `web/package-lock.json` pin validation/build dependencies. Vendored Urbit and Landscape file hashes are recorded in `docs/*source-provenance.json`.

## Setup and ownership

`python3 scripts/setup.py --install-tools` prepares the owned `.work/alpha/dev` fake ~zod, `.work/alpha/proxy` HTTPS supervisor, test certificates, dedicated Simulators, Firefox NSS profile, owner UI, and Xcode project. Omit `--install-tools` when XcodeGen and NSS already exist. The project-local Python environment is `.work/alpha/python`.

The owned manifest `.work/alpha/targets.json` derives a listener block and fixture ID from the source directory. Setup prints the actual HTTPS origin. HTTP, proxy, certificate-negative, unreachable, test-control and fresh-package ports are distinct. The matched fake-EAuth pair needs canonical UDP 31337/31338 in pinned Vere; setup refuses foreign owners of those ports. All other listeners remain checkout-specific. A cold pair waits for Eyre’s five-minute endpoint-cache boundary using the kernel clock. Do not expose fake-ship or test-control ports to the Internet.

Supervisors hold their own subprocess handles and private Unix sockets; stop/crash never act on a PID read from disk. Credentials, cookies, certificate keys, raw XCTest recordings and logs stay under mode-700 `.work/`. Native test logs can contain typed disposable login values and must not be shared. Only reviewed, sanitized evidence belongs under `artifacts/acceptance/`.

## Checks

```sh
python3 scripts/check.py --suite environment
python3 scripts/check.py --suite protocol
python3 scripts/test_hoon.py --suite state,auth,store,limits,codec,json,fixtures,http,entry,policy,integrations
python3 scripts/check.py --suite integration
npm --prefix web run typecheck
npm --prefix web test
npm --prefix web run build
python3 scripts/check.py --suite web
swift test --package-path sdk/swift
python3 scripts/ios_test.py --suite all
python3 scripts/ios_test.py --suite ui --small
python3 scripts/reload_rehearsal.py
python3 scripts/restore_rehearsal.py
swift test --package-path tests/consumers/swift
python3 scripts/benchmark.py
python3 scripts/package_desk.py --verify-install
```

The Hoon runner executes the actual shipped `-test /=connect=/tests/connect/<suite>` thread and rejects build failures or zero cases. Native package tests use Swift Testing; its final test count is authoritative even though the XCTest compatibility runner prints an initial zero-test summary. The iOS runner rejects missing/zero/skipped xcresults and prints sanitized counts only. The browser runner keeps raw reports private and trusts the project CA in its Node process as well as the dedicated Firefox profile; TLS verification remains enabled.

The standard Hoon gate includes `integrations`, including resource bearer rejection on the actual HTTP handler and ordinary document identity/revoke compatibility. Generic local resource exchange also has an independent live runner; it imports no adapter code and uses no adapter endpoints or defaults:

```sh
python3 scripts/test_resource_contract.py \
  --fixture-dir /absolute/project/.work/disposable-resource-test \
  --fixture-id explicit-owned-disposable-id \
  --origin https://localhost:19781 \
  --ca /absolute/project/.work/disposable-resource-test/tls/cert.pem \
  --owner-file /absolute/project/.work/disposable-resource-test/owner.json \
  --control-socket /absolute/project/.work/disposable-resource-test/pier/.urb/conn.sock \
  --vere /absolute/project/.work/disposable-resource-test/pier/.run
```

Select an already provisioned, disposable fake ~zod with Connect installed and its HTTPS issuer configured, two free client slots, and a private `.owned-fixture.json` containing exactly `{"project":"/absolute/project","fixture":"explicit-owned-disposable-id"}`. This marker must come from fixture provisioning; do not mark an existing personal/demo pier as disposable. All CA, owner and control paths must belong to that private fixture; the runner verifies ownership, loopback HTTPS, the live development endpoint and fake ship before writes. It installs only the generic `grant-probe` desk, registers two synthetic clients, and removes those clients and their namespaces in cleanup. Run it sequentially with other state-mutating checks; it does not provision, stop, or select a ship implicitly.

The live checks cover registration/scopes/callback binding, PKCE and single-use codes, kernel caller/response provenance, resource scry and revoke isolation, rejection of resource IDs and legacy ID-derived tokens as ordinary HTTP bearer credentials, owner revoke, and preserved document identity/revoke/strict refresh behavior. The Hoon handler regressions additionally reject valid legacy resource bearer tokens. `grant-probe` returns a fixed notes string: this demonstrates the reusable authorization contract, not a complete notes application. The sanitized scalar report stays at the selected fixture's `generic-contract.json`; raw credentials never enter command arguments or the report.

Acceptance deliberately registers eight development clients and resets their synthetic data. Use a fresh source checkout/development fixture for a new custom-client integration; the eight-client quota is intentional. The included todo registration remains usable after reapproval.

The native UI tests use the real system authorization browser and product SDK. Their private loopback TLS control server is excluded from the desk and app, and never supplies owner credentials to the SDK. Normal tests reset only the owned fake sample namespace. Real qualification uses a separately guarded `--real` scenario: it requires the explicitly authorized `connect-dev` marker, verified archives, normal system TLS and its own private owner-control tunnel. The prototype reset suite cannot select an arbitrary real origin. Browser automation of a real owner session requires explicit authorization to place its credentials in a private local test file.

The small-device check prepares a second dedicated iPhone SE Simulator. `scripts/export_native_evidence.py <private-xcresult> [--small]` exports only named product screenshots from a passing run; inspect these separately. Raw attachment exports stay private because automatic XCTest recordings can contain login input.

The browser runner also verifies a real five-minute pending-consent expiry. It prepares that request before the other browser checks and waits only for the remaining lifetime. Expect the complete acceptance run to take several minutes.

Run state-mutating suites sequentially. Owner bootstrap tokens and namespace/session changes can intentionally invalidate concurrent test contexts. Avoid rebuilding/reloading the desk while a native auth or timing scenario runs.

## Changing code

Edit `desk/`, `web/src/`, or `sdk/swift/`. After a web change, build and run `python3 scripts/bundle_web.py`; `desk/lib/connect-assets.hoon` is generated. After protocol fixture changes, run `python3 scripts/protocol_fixtures.py` and its `--check` mode. Stage with `python3 scripts/package_desk.py`; this checks actual compilation. Regenerate the Xcode project with `xcodegen generate --spec examples/ios-todo/project.yml` after file/target changes.

The runtime’s 64 GiB LMDB map setting is a pinned Vere 4.6 mitigation tested for this environment, not an upstream fix or a recommendation for arbitrary production piers. Local support scripts currently target Apple Silicon; source portability and physical-device signing are separate from this demonstrated environment.

Finish with `python3 scripts/cleanup.py`. It stops owned processes and removes test trust from the dedicated environments while retaining named piers, private logs, and reproducible evidence. Re-run setup before another test session. Certificates expire after 30 days; setup fails clearly if regeneration is required.

The HTTPS resource timeout is 45 seconds (35 seconds per request). During an unresolved network failure the UI can show a pending save until that timeout establishes Offline; it must never label an unacknowledged write Saved. The recovery UI test waits for that configured bound before terminating the app.

## Preserved-app upgrade prerequisite

Full qualification requires a real prior schema-1 Todo Simulator build and its matching `PackageFrameworks` SDK runtime. Before rebuilding that prior product, capture it with `scripts/capture_app_baseline.py --app <prior-ConnectTodo.app> --frameworks <prior-PackageFrameworks>`. This creates a private hash-bound baseline under the owned fixture and refuses replacement. This workspace captured the prototype build before alpha changes. A fresh source tree must supply that prior build explicitly; setup does not download an invented public prior release.

The upgrade test installs and launches the prior app through `simctl`, attaches XCTest by bundle ID, queues an offline edit, then installs the current app over it. Xcode's normal `XCUIApplication.launch()` reinstalls its current product, so it cannot be used to launch the historical baseline. The matching debug SDK framework is essential; mixing old app and new framework is an ABI mismatch. Actual schema versions, exact request/ID hashes, retained pairing, rejected editable input and one catch-up effect are recorded in `artifacts/alpha/app-update.json`. Ordinary source/Simulator use requires only the current build; this additional input is for the mandatory preserved-update qualification.

## Reference-host packet profiles

`netem_host.py` is reference-host test infrastructure. It creates an unprivileged user/network namespace and a bounded TCP relay, uses checksum-verified Debian ARM64 tools, and places `tc netem` rules only on relay-to-Eyre traffic inside that namespace. Only the private `connect-dev` Caddy upstream is switched temporarily. Existing trusted TLS and the personal ship's route remain intact. Named profiles add 100 ms RTT/1% egress packet loss or 500 ms RTT/5% egress packet loss to that upstream TCP connection. Record kernel qdisc counters with the measurements; an application-level dropped-response simulation is separate evidence.

Stop the owned controller to restore the original test upstream and terminate its own helper children. Never apply these rules to shared host interfaces. The real ship's private owner credentials remain on reference-host unless the owner explicitly authorizes a private local browser-test copy. Namespace and HTTP controls do not authorize publication or another ship.

## Real-host soak

`real_soak.py` runs once on the guarded reference host for 6 actual hours. It alternates mixed-size create/update/delete batches and 120-second idle periods, checks acknowledged content and identical receipt replay, and records post-cleanup RSS plus event-log/pier growth. It warms the same workload before taking its baseline and enforces the 15% memory tolerance only after the full period. Its grant and durable refresh-ambiguity marker remain in private remote `soak-state.json`; only scalar `soak.json` can be exported. The owner changed the duration from 72 to 12 hours on 2026-10-13, then authorized a fresh 6-hour test on 2026-10-14 after the memory investigation and bounded diagnostic. The original run failed at 3,840.017 seconds/32 cycles; the subsequent 12-hour run failed its RSS gate. Their start records, elapsed time, sources and private state remain failed evidence and cannot be credited to the fresh run. A failed or interrupted run is not restarted or counted as passed. The experiment uses a finite 7-hour user service with restart disabled and does not mutate other apps or piers.

Vere's demand-paged snapshots can change idle RSS several-fold without changing retained state. Both memory boundaries therefore run the same `%helm-mass` heap walk and sweep as the documented `|mass` on the verified test pier, then sample RSS immediately. A unique executed Dojo marker and ordered report frame prevent mixing older or partial output while accommodating normal terminal-log rollover. A checkpoint crossing invalidates that measurement; at most three identical attempts are allowed. Record anonymous/file-backed RSS, retained heap and Connect bytes, and boot/process-start identities. Both RSS and retained heap must remain within 15% of the warm boundary; any runtime replacement fails the counted run. These measurements do not reset caches, compact the pier, erase retained metadata or restart the ship. Raw terminal reports stay private on the reference host. The earlier 12-hour RSS failure remains failed evidence; this method requires fresh observation.

The guarded real native commands are `python3 scripts/ios_test.py --suite ui --real` for the system-browser workflow and compatible desk reload, and `python3 scripts/ios_test.py --suite unit --real` for the live SDK snapshot plus SQLite installation/foreground visibility probe at 100 ms RTT/1% packet loss. The SDK probe's private test presenter approves only its exact load-test client on the selected HTTPS origin; it does not prove system-browser interaction. Keep that distinct from the real UI case. These commands require the expressly approved private local owner-test file and must run before a counted soak: proxy outages and injected packet profiles would interrupt a normal-network observation period. Existing failed/interrupted evidence must be retained and inspected before starting a new full period.

Consent layout regressions run with `npm --prefix web run test:layout` using Chromium and WebKit against local Vite and synthetic API responses. `scripts/setup.py` installs both engines alongside Firefox; the full check runner includes this suite. Actual iOS system-browser consent remains separately demonstrated by native acceptance.
