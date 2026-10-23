# Supported updates

Before update, confirm ship identity, desk ownership, protocol/state compatibility and the new artifact hashes. If Connect holds documents, take a portable document export and verify it before changing the desk; it does not preserve grants or sessions. Do not rely on an older pier copy as a rollback for a ship that continues running. Preserve the installed Todo and its local data for the app-update check; the destructive acceptance runner’s normal reinstall does not demonstrate upgrade durability.

Stage/commit the compatible desk into the confirmed existing `%connect` mount. Validate `/connect/v1/info`, the bundled manager, sessions, documents, existing receipts, pending polls and outbox catch-up. Compatible reloads must retain grants and data. Do not rotate the restore generation merely for a normal compatible update.

Use the root/local `UrbitConnect` package and rebuild/install Todo over its existing Simulator app. Retain its per-app pairing, Keychain credentials, SQLite cache/outbox and exact queued requests. Supported SQLite migrations are transactional; an older SDK must refuse an unknown newer database without changing it. A test that uninstalls first does not count as this check.

If an update fails, pause new Connect writes and diagnose the exact version, compile or runtime error on the continuing ship. Preserve its current state and client drafts; do not restore an older pier or force an unsupported downgrade. Apply a compatible desk correction, then check documents, grants and client catch-up before resuming writes. A portable document export can recover content on a different installation, but clients must reauthorize there.

Record actual install/update observations and their scope. Independent operator signoff is not a readiness gate. Do not present an unobserved profile as demonstrated.
