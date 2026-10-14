# Supported updates

Before update, confirm ship identity, desk ownership, protocol/state compatibility, the new artifact hashes and a verified recovery backup. Preserve the installed Todo and its local data for the app-update check; the destructive acceptance runner’s normal reinstall does not demonstrate upgrade durability.

Stage/commit the compatible desk into the confirmed existing `%connect` mount. Validate `/connect/v1/info`, the bundled manager, sessions, documents, existing receipts, pending polls and outbox catch-up. Compatible reloads must retain grants and data. Do not rotate the restore generation merely for a normal compatible update.

Use the root/local `UrbitConnect` package and rebuild/install Todo over its existing Simulator app. Retain its per-app pairing, Keychain credentials, SQLite cache/outbox and exact queued requests. Supported SQLite migrations are transactional; an older SDK must refuse an unknown newer database without changing it. A test that uninstalls first does not count as this check.

If an update fails, stop new traffic and diagnose the exact version/compile/runtime error before restoring. A restored old pier is a rollback with a recovery-point loss window, not an ordinary compatible update. Follow `operations.md`: isolate ingress/Ames, restore a verified backup, rotate to a fresh generation through owner authority, reject old clients and explicitly reconcile drafts before reopening. Preserve the newer local cache and drafts if a downgrade is unsupported.

Record actual install/update evidence and required independent operator signoff in the alpha matrix. Do not mark an untested profile supported.
