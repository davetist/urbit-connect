# Known limitations

- Local source/Simulator candidate with a tested connect-dev Linux ARM64 install/update path. Real native qualification, the 6-hour soak, independent developer/operator trial and release provenance must meet the alpha matrix before qualification. Public distribution is pending separate authorization.
- Native publisher identity is unverified. Public IDs/labels/custom-scheme registrations are not proof of which app binary initiated a fresh flow. Known apps require explicit ship consent every time a new grant is created.
- The host/runtime/installed code/TLS terminator and consuming app are trusted. Documents are ship-readable; an app can copy readable data. No host-blind E2EE or federated Urbit identity is claimed.
- iOS 18+ is the compile floor; actual evidence names Simulator runtime/layouts. Physical phones, public TestFlight/App Store, claimed HTTPS callbacks, companion/broker and registry services are deferred.
- Conservative document/request/app/session/snapshot and local outbox budgets apply. Todo stores each list in one 16 KiB document; preserve a rejected input and use another list when full.
- Restore detection is an operator procedure, not automatic proof of rollback. Rotate a fresh generation before reopening restored ingress and deliberately reconcile drafts. Backups omit later acknowledged writes and edits never sent by the device.
- Logical removal/erase does not erase historical pier events, snapshots outside Connect or backups. Uninstall/device loss can lose local-only drafts.
- The real HTTPS profile uses Tailscale Serve and requires tailnet access. General public-domain ingress and other host profiles are unqualified. reference-host’s personal ship is excluded. Providers that disallow custom desks are unsupported.
- The source owner/contact and public publishing authorization remain pending. The authorized root license is MIT; authentic upstream notices and the licensed Landscape-source comparison are included.
