# Contributing locally

The source repository is [davetist/urbit-connect](https://github.com/davetist/urbit-connect). The owner authorized committing this workspace to that private repository on 2026-10-14. Public releases remain separate: source ownership and maintenance/security contacts are still awaiting designation in `release/ownership.json`.

Use `development.md` to prepare the owned fixtures. Preserve unrelated source changes and the original demo, and run mutating browser/native/ship suites sequentially. Changes to protocol authority, storage, retry or migration behavior need a meaningful regression and the applicable current-source checks. Keep successful enqueue distinct from acknowledged ship save, restore fencing distinct from compatible update, and data export distinct from diagnostics.

Run the complete acceptance check and inspect actual UI evidence before preparing a release candidate. `release_check.py` builds unsigned local artifacts and records source/evidence hashes; `qualify_alpha.py` keeps missing human/elapsed/provenance gates visible. Never include `.work` credentials, piers, raw recordings or signing material in an artifact. See `support.md` for private diagnostic reporting and `alpha-handoff.md` for independent qualification.
