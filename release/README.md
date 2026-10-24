# Local release inputs

The source release is `0.2.0`, protocol 1. The root license is MIT; preserve authentic Urbit notices and Landscape provenance in the archives. `ownership.json` records the source owner, maintenance and private-security contacts, and publication authorization.

This release includes the owner-login split-cookie correction, scoped and atomic document operations, durable Swift SDK offline queues and recovery, and the bundled Connect manager. The current desk passed 75 Hoon checks, six native document workflows, 63 Swift SDK tests, two public-consumer tests and a focused Todo iOS Simulator workflow. [Current evidence](../docs/current-readiness.md) and the [focused security review](../docs/security-review-2026-10-24.md) state the exact boundaries. Physical-device behavior and a signed native phone download are outside this release.

On 2026-10-24, a separate running 408k ship installed the published desk through `|install`. Tire reported `%live` with no queued update, and its `/connect/v1/info` endpoint returned JSON with HTTP 200. This verifies distribution from the stable publisher; client workflows are covered by the separate evidence linked above.

`release_check.py --build` binds source files, generated web assets, desk/SDK/Todo archives, toolchain pins and historical observation files by SHA-256. It builds twice to check deterministic packaging, without running tests or booting ships. `--verify release/manifest.json` checks those source/artifact/evidence bytes. Source hashes provide integrity, not an acceptance requirement that every old observation match new source.

Manifest format 2 reports `readinessPolicy: informational`; it issues no qualification verdict. The compatibility-named `qualify_alpha.py` only summarizes existing observations and never launches a full suite. Missing human observations, elapsed time, participant counts and different source identities do not block daily use. Historical `qualified` fields remain historical; no record is rewritten to claim success.

The source desk, SDK and Todo archives are unsigned source deliverables, not signed iPhone downloads. Publish only the reviewed desk files from the manifest; keep unfinished working desks and alpha updates separate.
