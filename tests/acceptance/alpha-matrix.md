# Reliability alpha qualification matrix

All evidence must match the final release source/artifact identity and owned targets. A pending/zero/skipped required row blocks qualification. Historical prototype results, self-written docs and fake-ship checks cannot substitute for real-host or independent-human evidence.

| Gate | Required evidence |
|---|---|
| T01 isolation | Cross-checkout/old-demo/port/Simulator refusal; baseline nonzero counts; demo retained; reproducible two-build hashes |
| T01 provenance | Root MIT; authentic Urbit/Landscape notices; clean artifact hashes |
| T02 approval | Real browser approve/deny/cancel; exact callback/PKCE/state/code/expiry; owner-only registration; scope/namespace/CSRF/malformed/oversized checks |
| T03 reload/retry | Pending-poll reload reproduction and sanitized classification; 100 reloads; 1,000 withheld mutation responses; refresh ambiguity; no duplicate effects/data or credential loss |
| T04 offline/limits | Terminate/reopen/sync; exact count/byte limits; quota release; disk-full/commit rollback; retained editable input; explicit CAS conflicts; server resource bounds/fairness |
| T05 restore/migration | Twice restore the same actual backup; fresh generations; old tokens/cursors/receipts/queued creates fenced; loss window; two independent operator rehearsals; pending-work upgrades/newer-schema refusal |
| T06 manager/pairing | Generic setup and explicit sample; copyable origin/known-path confirmation; rename/disable/re-enable/revoke/remove; old consent invalid; fresh namespace; draft-preserving refresh |
| T07 SDK/Todo | Root/local package; clean unsigned build; public-interface distinct-schema compilation; in-place app update; lifecycle/storage/Keychain failures; both Simulator layouts and visual/accessibility evidence |
| T07 independent developer | Unfamiliar developer creates distinct schema from docs; registers and authorizes without SDK fork/copied TodoStore/staff enrollment; CRUD/conflict/revocation; records setup and first round trip |
| T08 real install/update | Confirmed Linux ARM64 real test ship; trusted HTTPS/renewal/ingress; fresh/update/partial/wrong-version/certificate/space cases; preservation; independent owner/operator procedure |
| T09 latency/load | Real host: 1,000 docs/4 MiB, eight apps, 32 sessions, four snapshots; local p95 CRUD <1s; 100ms/1% loss p95 <2s, visibility <5s, snapshot+install <30s; 500ms/5% loss safe recovery |
| T09 soak | 6 actual hours of real-host churn/idle; no integrity failure/hang/unbounded retention; post-cleanup RSS and retained heap within 15% warm baseline; disk/event-log growth measured |
| T09 security/privacy | Focused independent auth/storage/HTTP/Gall/SDK review; fix authority/data-loss findings; canary-redacted local diagnostics/report/export checks; publisher limitation explicit |
| T10 practical trial | 2–3 authorized owner/developers, seven actual days, offline recovery and desk update; integrity findings fixed and reobserved; first-save/setup timings separated |
| T10 local delivery | Final complete checks; honest limitations/support/backup docs; reproducible desk/SDK/Todo archives; reconciled manifest |
| T10 public delivery | Source owner and maintainer/security contacts; separately authorized exact channels and verified clean retrieval/install. These publication-only inputs do not block private qualification; if unapproved, report local availability only |

Deferred: physical-device qualification, public TestFlight/App Store, associated-domain publisher identity, companion/broker, registry/verifier services and additional host profiles.
