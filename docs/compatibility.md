# Compatibility and recovery

| Desk / protocol | Swift SDK / source | State and cache |
|---|---|---|
| Prototype 0.1.0 / protocol 1 | Prototype 0.1.0 | Gall state 1; SQLite 1 |
| Reliability development 0.2.0-alpha.1 / protocol 1 | 0.2.0-alpha.1 | Gall state 1; transactional SQLite 1→2 upgrade preserves pending requests; unknown newer schemas refused |

The alpha adds reliability and owner controls to protocol 1. It retains the prototype’s callback, PKCE, state, rotating refresh, scopes and JSON document contract. The local package workflow is supported until source ownership, notices and publishing channels are finalized. Release rows do not certify runtime/device behavior: historical observations are in `artifacts/alpha/report.md`, and current changes are in `current-readiness.md`.

The SDK preflights `/connect/v1/info` before consent and before synchronization. It requires protocol 1, a configured HTTPS issuer at the entered origin’s `/connect`, a persistent instance ID and the pinned restore generation. It rejects a missing or incompatible desk before mutation and does not follow arbitrary endpoint redirects. The ship name is the endpoint’s assertion, not a globally verified ship identity.

A compatible restart/reload retains sessions and confirmed records. Availability failures are retried with bounded backoff; malformed successful protocol responses fail closed. An explicitly rejected grant, changed issuer/instance or restore generation requires reauthorization and deliberate draft review. A lost refresh response is ambiguous because the server may already have rotated its single-use refresh token. Never replay it to conceal that uncertainty; reconnect on the ship instead. New authorization always displays consent.

Queued edits are durable local work, not acknowledged ship saves. In-place supported cache upgrades preserve mutation IDs and request bytes. Unknown newer cache schemas are rejected without changing their contents. A restored ship cannot reconstruct unsent edits or writes after the backup’s recovery point. Export retained drafts before replacing an account, uninstalling or removing local storage.
