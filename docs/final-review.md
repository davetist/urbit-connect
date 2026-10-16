> Historical implementation/review record. Earlier quotas, commands and qualification gates below are superseded by `current-readiness.md` and `capacity.md`; prior passes are not claims for changed source.

# Independent implementation review

A fresh-context reviewer inspected the complete authored desk, SDK, owner UI, native sample, tests, tooling and documentation. The review was read-only and did not access private credentials or alter the running fixtures. It identified no Critical findings and four Important findings. The author retained responsibility for the fixes and final runtime acceptance; no second review substitutes for regression testing.

| Finding | Reproduction and correction | Status |
|---|---|---|
| Delayed owner selection/refresh can mix app identity and document rows | Browser tests deliberately reorder real responses with matching IDs/revisions in two namespaces. Both failed on the stale rows. Selection and rows now install atomically under a request generation. | Both browser regressions RED→GREEN and pass in the full browser batch |
| Pretty-printed export can exceed the importer limit | Actual export path produced an over-limit file from 300 valid structured documents (3.60 MB live payload). Compact output passes the same bounded import parser and preserves all data. | Regression RED→GREEN; 19 web tests pass |
| Superseded disconnect can clear a newer account | Delayed revoke followed by a new account reproduced loss of credentials, cache and pending status. Final mutation now checks the captured generation. | Regression RED→GREEN; SDK suite passes |
| Foreground during pairing can resume old-account synchronization/refresh | Delayed authorization and refresh reproduced old-account activity and credentials overwriting the new account. Pairing cannot start sync; installation invalidates older work; refresh entry points check generation. | Regression RED→GREEN; SDK suite passes |
| Connected screen hides endpoint/development identity (reviewer: Minor) | Regraded Important because the explicitly paired HTTPS endpoint is the prototype's actual identity boundary. Native UI test failed on missing endpoint. SDK now persists development metadata; native screen displays origin and a Development ship label. | SDK persistence test and both native UI workflows pass in final combined verification |

The complete Swift suite has 40 passing cases after these corrections. The final combined run passed all 210 cases with no skipped tests. Rendered evidence, fresh installation, deterministic packaging, and owned-resource cleanup also passed; see the [acceptance report](../artifacts/acceptance/report.md).

## Scope rulings

The review excluded physical-device signing/execution, Internet deployment, production ships, publication, independently verified global Urbit identity, host-blind encryption, malicious native app/desk/host/TLS-terminator protection, upstream implementation auditing/public licensing readiness, and an entitled macOS sample application. These exclusions match the agreed local iOS Simulator prototype and its documented trust model. They remain separate future work; this implementation does not claim those properties. Final runtime, visual and cleanup verification remained the implementer's responsibility and is tracked by A1–A12.

No minor finding was silently dropped. The only Minor finding was elevated and included in the fix pass. All four Important findings were accepted.

A related editor formatting issue was subsequently reproduced with the actual editor decoder: pretty whitespace could exceed its raw-input limit despite a valid compact payload. The corrected decoder separately bounds formatted input (1 MiB) and stored JSON (16 KiB); the focused regression passes, and the final browser suite includes saving the structured document through the real manager.
