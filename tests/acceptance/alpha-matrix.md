# Connect observation map

This replaces the former binding qualification matrix. There are no minimum soak hours, trial days, tester/operator counts or independent signoffs. The rows describe useful evidence categories, not gates. Existing reports retain their original outcomes and source identity; none is automatically evidence for later changes.

| Area | What an observation can establish |
|---|---|
| Authorization | Actual consent, exact callback/PKCE/state, owner access, expiry, revocation and scope enforcement under the recorded conditions |
| Storage | Atomic mutations, conflict handling, exact receipt replay, tombstone behavior and recoverable local drafts |
| Recovery | Compatible reload/migration and explicit restore generation handling on the observed runtime |
| User interaction | Actual browser/native behavior on the devices and layouts used |
| Integration | The client versions and end-to-end workflows actually exercised |
| Operations | Install/update/backup/restore behavior on the selected host and artifact |
| Resources | Measured latency, memory, disk and event history under the stated workload; no universal capacity promise |
| Packaging | Deterministic artifacts, complete notices and source/file integrity |

The continuing owner direction defaults to static inspection, AST/typechecking/build and deterministic packaging. No synthetic, unit, integration, fixture, native or soak workloads should run unless the owner explicitly changes that direction; separately authorized actual official-client workflows remain distinct. None of those test workloads ran for the quota/gate cleanup. See `docs/current-readiness.md` for the current boundary and `docs/capacity.md` for retained controls.
