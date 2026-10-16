# Current-source readiness — 2026-10-16

Connect remains a reliability alpha candidate. The current standalone `%connect` and `%bitwarden` desks have now been exercised together with official Bitwarden clients, after the repository split and token-identifier repairs. The [Bitwarden acceptance record](https://github.com/davetist/urbit-bitwarden/blob/main/evidence/current-2026-10-16/assessment.md) contains the exact source hashes, client versions, results and qualifications. This is evidence for the generic local-resource contract; Bitwarden protocol and vault behavior remain in the separate repository.

## Demonstrated integration

Fresh SSO/local unlock and initial sync passed in official CLI 2026.9.1, Chrome extension 2026.9.3, signed macOS desktop 2026.9.1, and an unchanged official iOS 2026.9.1 (3533) source build in Simulator. Extension password edit/autofill, desktop and iOS note edits, cross-client sync, CLI four-type/folder/export-import workflows, native refresh retry/restart and stopped-pier restore/decryption passed. Connect owner revocation denied subsequent official CLI sync; the extension showed its login screen after revocation.

The first CLI sign-in attempt failed before a fresh-profile retry passed; its cause is unconfirmed. The iOS consent page required reduced Safari page scale to reach approval. These remain readiness qualifications. No Android installed-client, physical-device, App Store iOS, Windows/Linux desktop, immediate-push or production-security claim follows from this run.

## Connect acceptance and test repairs

The complete current-source automated run is recorded in [the check summary](../artifacts/current-2026-10-16/check-summary.json). It rejects skipped or empty suites. Native and browser checks ran sequentially against owned fixtures, including the actual five-minute consent expiration.

The initial native run failed the preserved-install upgrade case because XCTest could relaunch the old app with the current Swift SDK framework. The crash log identified the newer framework UUID in the old process. The harness now returns the validated preserved framework path, XCTest retains it while attaching to the old app, and removes it before launching the updated app. The original migration, queued-request byte/hash and capacity assertions remain intact. The focused regression passed after the fix (one test, no skips).

The pre-existing uncommitted tooling/browser changes were preserved and reviewed: SDK consumer cache identity, cleanup ownership, startup-failure cleanup, browser action waiting and generated web assets. An independent read-only review found no actionable defects; its focused tooling checks and asset byte comparison passed.

## Qualification boundary

Automated acceptance and the Bitwarden workflows establish a usable local development candidate. They do not complete the [alpha release checklist](release-checklist.md). Real-host qualification, independent operator/developer and authorization/storage review, a current-candidate six-hour soak and the seven-day practical trial remain separate gates. The prior six-hour run applies to its frozen candidate, not automatically to this source tree. Public distribution metadata remains separate from private qualification.

The release manifest is regenerated from current source/artifacts/evidence. A `qualified: false` result is intentional while these gates are incomplete. Existing unrelated fixtures and real ships are preserved. The Bitwarden test used its own disposable fake ship, isolated client profiles and Simulator trust.
