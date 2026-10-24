# Focused Connect security review — 2026-10-24

The current desk runtime source is byte-identical to commit `b2eee06e0478dc3ddeadceebb842959938ff1cb5`; later changes through `ed5dc200283d413dcef12c5d1b397da8eceb2ab1` affect packaging and documentation. A read-only source review found no confirmed vulnerability in owner-cookie/CSRF handling, OAuth consent and PKCE, token refresh/revocation, document scopes, or same-ship integration grants.

The owner route requires authenticated local delivery and binds CSRF to the joined Cookie fields and exact Origin. OAuth codes bind client, callback and PKCE; refresh rotates credentials and replay revokes the session. Integration pokes require the registered same-ship agent, and grant scries recheck live authorization. Direct native-Eyre owner bootstrap passed with both one and two Cookie headers. The current desk also passed 75 Hoon regressions and six native document integration tests; the public Swift SDK and Todo Simulator results are in [candidate evidence](../artifacts/alpha/current-document-sdk-2026-10-24.json).

This is a focused review of those paths, not a complete independent security audit or physical-device test. Publisher identity and an app's ability to copy data it can display remain documented trust limits.
