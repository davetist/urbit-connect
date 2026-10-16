# Local release inputs

The local release is `0.2.0-alpha.1`, protocol 1. The root license is MIT; preserve authentic Urbit notices and Landscape provenance in the archives. `ownership.json` records publication metadata separately from local use.

`release_check.py --build` binds source files, generated web assets, desk/SDK/Todo archives, toolchain pins and historical observation files by SHA-256. It builds twice to check deterministic packaging, without running tests or booting ships. `--verify release/manifest.json` checks those source/artifact/evidence bytes. Source hashes provide integrity, not an acceptance requirement that every old observation match new source.

Manifest format 2 reports `readinessPolicy: informational`; it issues no qualification verdict. The compatibility-named `qualify_alpha.py` only summarizes existing observations and never launches a full suite. Missing human observations, elapsed time, participant counts and different source identities do not block daily use. Historical `qualified` fields remain historical; no record is rewritten to claim success.

Public publication, publisher identities and external messages require separate authorization. A local source archive is not a signed iPhone download.
