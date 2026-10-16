# Current status — 2026-10-16

**Consent follow-up:** the default-scale iOS consent issue is now fixed and verified in the official app’s system browser. See the [layout correction and current rerun](consent-layout.md).

Connect remains a reliability alpha candidate. The pre-cleanup standalone `%connect` and `%bitwarden` versions were exercised together with official Bitwarden clients after the repository split and token-identifier repairs. Those observations do not cover the later quota, pagination or snapshot-lease changes. The [Bitwarden acceptance record](https://github.com/davetist/urbit-bitwarden/blob/main/evidence/current-2026-10-16/assessment.md) contains the exact source hashes, client versions, results and qualifications. This is evidence for the generic local-resource contract; Bitwarden protocol and vault behavior remain in the separate repository.

## Demonstrated integration

Fresh SSO/local unlock and initial sync passed in official CLI 2026.9.1, Chrome extension 2026.9.3, signed macOS desktop 2026.9.1, and an unchanged official iOS 2026.9.1 (3533) source build in Simulator. Extension password edit/autofill, desktop and iOS note edits, cross-client sync, CLI four-type/folder/export-import workflows, native refresh retry/restart and stopped-pier restore/decryption passed. Connect owner revocation denied subsequent official CLI sync; the extension showed its login screen after revocation.

The initial run exposed a CLI first-sign-in failure and required reduced Safari page scale on iOS. The subsequent [consent layout fix](consent-layout.md) passes at default scale. Bitwarden’s [initial-token compatibility correction](https://github.com/davetist/urbit-bitwarden/blob/main/evidence/cli-signin-fix-2026-10-16/assessment.md) then passed 16/16 fresh-profile CLI sign-ins without retries. At that historical follow-up, Connect executable sources were unchanged from the consent-fix acceptance run. The subsequent quota/gate cleanup changes source and is not covered by that run. No Android installed-client, physical-device, App Store iOS, Windows/Linux desktop, immediate-push or production-security claim follows from this run.

## Connect acceptance and test repairs

The prior automated run is recorded in [the check summary](../artifacts/current-2026-10-16/check-summary.json). It rejects skipped or empty suites. Native and browser checks ran sequentially against owned fixtures, including the actual five-minute consent expiration.

The initial native run failed the preserved-install upgrade case because XCTest could relaunch the old app with the current Swift SDK framework. The crash log identified the newer framework UUID in the old process. The harness now returns the validated preserved framework path, XCTest retains it while attaching to the old app, and removes it before launching the updated app. At that point the original migration, queued-request byte/hash and capacity assertions remained intact; the subsequent cleanup archives obsolete quota assertions while retaining migration/replay coverage. The focused regression passed after the fix (one test, no skips).

The pre-existing uncommitted tooling/browser changes were preserved and reviewed: SDK consumer cache identity, cleanup ownership, startup-failure cleanup, browser action waiting and generated web assets. An independent read-only review found no actionable defects; its focused tooling checks and asset byte comparison passed.

## Current quota and reporting changes

Artificial document/storage, app/session and local offline/draft quotas are removed. Pagination uses the actual result size; snapshot leases renew with valid progress, including time for throttled continuation retries. JSON shape, authorization, atomicity, conflict handling and the specific transient/replay controls in [capacity.md](capacity.md) remain. Removing quotas does not establish performance at arbitrary scale.

Mandatory soak/trial durations, tester/operator quotas, independent signoffs and source-matched evidence as daily-use prerequisites are retired. The release manifest now uses `readinessPolicy: informational`; the reporting command reads observations without producing a qualification verdict. Source/artifact/evidence hashes still protect integrity.

The earlier results above remain historical evidence for their recorded sources. The quota/gate cleanup is limited to static source review, Python AST parsing, Swift/TypeScript compilation/build and deterministic packaging. No synthetic/unit/integration/fixture/native tests or soaks were run or are claimed for the changed behavior. The owner's no-synthetic/no-soak direction continues for future changes unless explicitly changed: default to static/build review and separately authorized actual official-client workflows, with no mandatory test gates. No live ship, deployment or user data was changed by this cleanup.
