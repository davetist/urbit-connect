# Remaining independent alpha checks

The current implementation and automated evidence are in `artifacts/alpha/report.md`. Required human and elapsed-time checks remain open until performed against the exact release manifest. An automated reviewer or a team-authored example does not count as an independent operator/developer or a practical tester.

## Operator

Use a separately authorized disposable ship on the named Linux ARM64 profile, normal trusted HTTPS and a verified recovery backup. Follow `install.md` and `update.md` without live coaching. Record desk/SDK/archive hashes, prerequisites, setup time and first successful Todo save separately. Preserve grants, documents, receipts and a queued edit across a supported desk update. Follow `operations.md` for two isolated actual-backup restores, checking the recorded recovery point, fresh generation, old-grant/cursor rejection and deliberate draft reconciliation. Never bring two copies of a real ship online together.

Record operator identity, date, target authorization, version/hashes, steps, actual result and reviewed credential-free evidence. The two-operator restore gate requires another operator in addition to the existing automated rehearsal; it is not satisfied by running the same script twice under a different name.

## SDK developer

Start from `sdk-integration.md` and the root/local package. Create a distinct document schema without copying TodoStore or forking the SDK. Register the app through the ship manager, authorize through the ship browser, and demonstrate CRUD, an explicit conflict, offline termination/catch-up, revoke and reauthorize. Report prerequisites/setup time and first round trip separately; the target is half a day after the ship/Xcode prerequisites are ready. The included notes consumer demonstrates public API compilation and is not independent-developer signoff.

## Practical testers

The owner selects 2–3 consenting owner/developer testers and their authorized test setups. Each uses the source/Simulator flow for seven actual days, including an in-place desk update and offline recovery. Record dates, artifact identity, observed failures and reviewed evidence. Do not share owner codes, cookies, tokens or private recordings. An integrity or authority defect requires a fix and a relevant new observation period before release.

## Release inputs

Source owner and maintenance/security contacts in `release/ownership.json` are deferred publication metadata. They do not block the private alpha or the technical checks above. Preserve the authentic notices and the licensed Landscape-source comparison. Explicit authorization of exact publishing channels is separate from local construction. Populate `artifacts/alpha/manual-evidence.json` only with performed, linked evidence; `qualify_alpha.py` rejects absent, shortened or stale gates.
