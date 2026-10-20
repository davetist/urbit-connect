# Known limitations

- Local source/Simulator release with historical Linux ARM64 install/update evidence. No soak, timed trial or independent signoff is a daily-use gate. The quota/gate cleanup has static/build validation only; prior runtime results do not prove changed behavior. The owner's no-synthetic/no-soak direction remains in force for future work unless explicitly changed. Public distribution is separate.
- Native publisher identity is unverified. Public IDs/labels/custom-scheme registrations are not proof of which app binary initiated a fresh flow. Known apps require explicit ship consent every time a new grant is created.
- The host/runtime/installed code/TLS terminator and consuming app are trusted. Documents are ship-readable; an app can copy readable data. No host-blind E2EE or federated Urbit identity is claimed.
- iOS 18+ is the compile floor; actual evidence names Simulator runtime/layouts. Physical phones, public TestFlight/App Store, claimed HTTPS callbacks, companion/broker and registry services are deferred.
- Product data/account/outbox quotas are removed. Parser, transient-concurrency, credential-lifetime and replay-history controls remain explicit in `capacity.md`. Available host/device resources still bound practical scale.
- Restore detection is an operator procedure, not automatic proof of rollback. Rotate a fresh generation before reopening restored ingress and deliberately reconcile drafts. Backups omit later acknowledged writes and edits never sent by the device.
- Logical removal/erase does not erase historical pier events, snapshots outside Connect or backups. Uninstall/device loss can lose local-only drafts.
- The real HTTPS profile uses Tailscale Serve and requires tailnet access. General public-domain ingress and other host profiles are unqualified. Dedicated test ships must remain separate from production ships. Providers that disallow custom desks are unsupported.
- The source owner/contact and public publishing authorization remain pending. The authorized root license is MIT; authentic upstream notices and the licensed Landscape-source comparison are included.
