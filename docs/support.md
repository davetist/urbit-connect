# Support and diagnostics

The maintainer and private security contact are pending owner designation in `release/ownership.json`. This is a local reliability candidate, not a publicly available native phone app. Use the supported source/Simulator workflow and report the exact desk/SDK/Xcode/runtime versions.

For pairing, copy the HTTPS base address from the ship manager. Confirm the offered base origin for a known manager URL; other paths, redirects and invalid certificates are refused. Distinguish an unreachable host from a missing desk, unconfigured issuer, unsupported version or changed instance. Never turn off TLS verification to get past an error.

For offline work, keep the device’s local storage. Wait for an acknowledgement before calling a change saved on the ship. A storage failure leaves existing drafts intact and must leave the rejected input editable. Export/reconcile drafts before uninstalling or replacing an account. Revoked/ambiguous-refresh/restored accounts need ship consent again; lost refresh responses must not be replayed.

Use read-only `python3 scripts/doctor.py https://your-ship.example --output diagnostic.json` to create a private local diagnostic export. It refuses overwrite and uses a fixed field allowlist; owner/scoped credentials and document content are excluded. A practical report also contains: version/hash; supported platform; status/error category; timing; exact steps using synthetic content; expected/actual behavior; whether work remains locally queued; and reviewed screenshots. Omit owner codes, cookies, bearer/refresh tokens, PKCE/state/code values, document bodies, task titles, raw XCTest recordings and private `.work` files. Share exported data only deliberately with its owner; a data export is not a diagnostic report.

A security or data-integrity defect blocks release. Preserve the evidence and affected drafts privately, fix and rerun the relevant matrix, then reconcile the final release manifest. Do not invent a status service or message testers without authorization.
