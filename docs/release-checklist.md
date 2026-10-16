# Release preparation

This is packaging guidance, not a permission or readiness gate for daily use. Connect has no mandatory soak duration, tester/operator quota, independent developer signoff, practical-trial period or all-tests qualification verdict.

Build the local desk, web, Swift SDK and Todo source artifacts with `python3 scripts/release_check.py --build`. This performs deterministic builds and compares archive hashes; it does not boot ships or run suites. Verify a prepared manifest with `python3 scripts/release_check.py --verify release/manifest.json`. Preserve upstream notices and keep private credentials, piers and raw recordings out of archives.

`python3 scripts/qualify_alpha.py --release-manifest release/manifest.json` summarizes available observations. Missing observations and source mismatches are visible context, never a pass/fail readiness decision. Historical results describe only the sources and conditions actually exercised. Report current changes and unverified behavior plainly; do not manufacture `qualified: true` or reuse a prior test pass as current evidence.

Publication still needs authorization for the exact destination and required ownership/contact metadata. Local artifacts are source deliverables; native signing, physical-device behavior and public distribution are separate work.
