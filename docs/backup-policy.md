# Backup and draft recovery policy

Keep verified full-pier backups with checksums, private access and recorded recovery points. Test restoration on an isolated authorized fixture; a real identity clone must not run concurrently on Ames. Portable document exports do not include the complete pier, sessions, receipts, revision history or event log.

A stopped-pier backup recovers only its known point. Writes acknowledged later are outside that backup. Record the loss window rather than claiming recovered data contains them. The ship cannot back up edits that remain only in a device outbox. Device uninstall/loss can lose those drafts; export them deliberately before removing local storage or replacing an account.

For restore: isolate ingress and network/Ames; verify and restore the backup; keep owner access private; rotate to a fresh generation using runtime entropy and revoke old sessions; verify old tokens/cursors/queued writes are refused; compare documents to the recovery point; then reopen. An ordinary compatible restart/update does not rotate the generation.

Retain pending device drafts through supported cache migrations and reauthorization, mark changed generations/namespaces for review and preserve exact requests until their outcome is known. Export/reconcile retained-account drafts explicitly. A cache budget may discard only recoverable confirmed data; it must never silently evict unsent work.

Two operator rehearsals of the same actual backup, including different intervening timelines, are required release evidence. The owned fake-ship rehearsal is useful automated proof, but cannot substitute for those independent real-target procedures.
