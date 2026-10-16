# Contributing locally

The source repository is [davetist/urbit-connect](https://github.com/davetist/urbit-connect). Keep Connect's generic authorization, document protocol and SDK separate from resource-specific clients and storage.

Preserve unrelated changes. Keep successful enqueue distinct from acknowledged ship save, restore fencing distinct from compatible update, and data export distinct from diagnostics. Authentication/authorization, exact-byte replay, atomicity and conflict rules remain requirements.

The owner's continuing direction is no more synthetic or soak tests. Do not run synthetic/unit/integration/fixture/native test workloads or soaks for future changes unless the owner explicitly changes that direction. Default to static source review, AST parsing, typechecking/builds and deterministic packaging; demonstrate actual official-client workflows only when that real interaction and target are authorized. Generic TDD or release workflows must not reintroduce synthetic checks or mandatory test gates. `check.py` has no `--all` path; its remaining explicit-suite entry points are historical tooling, not authorization to run them. The old soak command and service are retired.

`release_check.py` builds unsigned local artifacts and records source/artifact/evidence integrity. `qualify_alpha.py` reads observations without qualification gates. Never include `.work` credentials, piers, raw recordings or signing material in an artifact. Publication authorization and destination metadata remain separate from local use.
