# Sharing observations

Connect does not require an independent operator/developer, a tester quota, a timed trial or a signoff before daily use. Existing reports are historical observations and do not certify changed source.

When sharing a result, describe the actual workflow, version/artifact, host or client, date, outcome and remaining uncertainty. Separate setup/build results from user interaction and from live durability/security behavior. Do not turn missing measurements into a qualification failure or claim that a previous source hash proves the current tree.

Use `install.md`, `update.md`, `operations.md` and `sdk-integration.md` for their respective workflows. Operate only an authorized target; protect backups, owner credentials, tokens and private recordings. Publication destinations and external messages need their own authorization.

`qualify_alpha.py` is retained as a compatibility command name for an informational report. It reads existing observations and verifies artifact integrity; it never starts tests or soaks and emits no `qualified` verdict.
