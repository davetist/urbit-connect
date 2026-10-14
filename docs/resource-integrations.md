# Local resource integrations

Connect can authorize a local Gall resource agent as well as its existing document API. This is an opt-in extension of protocol 1, not an OpenID Connect provider or general OAuth compatibility promise. Ordinary document clients retain their existing callbacks, opaque tokens, namespace isolation and strict refresh-reuse revocation.

An owner registers an immutable resource policy through `POST /connect/owner/v1/clients`, with the usual authenticated Eyre cookie, Origin and X-Connect-CSRF checks:

```json
{"id":"notes-native","name":"Native notes","redirectURI":"http://localhost:18065/callback","integration":{"agent":"grant-probe","scopes":["notes:read"],"redirectURIs":["http://localhost:18065/callback"]}}
```

The primary redirect must appear in the allowlist. Up to eight explicit callbacks and resource scopes are accepted. Resource scopes cannot start with `documents:`. Explicit HTTP loopback callbacks allow only `localhost` or `127.0.0.1`, an unprivileged canonical port and an exact path; no wildcard ports, userinfo, query, fragment or backslash. Other callback validation remains unchanged. Owner approval displays the resource agent and requested scopes and explains that the resource manages its own data. The registration's policy cannot be mutated; removal and new registration create a new namespace/epoch boundary.

The existing `/connect/oauth/authorize` performs state/PKCE validation and ship-owner consent. Resource codes cannot be exchanged at the generic HTTP token endpoint. The registered local resource sends `%connect-exchange` with the mold in `sur/connect.hoon`:

```hoon
[request=@t client=@t code=@t redirect=@t verifier=@t]
```

Connect checks both the local ship and kernel-provided caller path `/gall/[registered-agent]`. It applies the existing short-lived, single-use, exact-client/callback, S256 code exchange. It pokes the calling agent with `%json` containing `request`, numeric `status`, and `grant` (the existing grant object on success; an error value otherwise). The resource must authenticate this response as local `/gall/connect` and correlate its request ID.

A resource reads `%gx /~ship/connect/[time]/integration/[agent]/[session-id]/json`. The result is a current grant or JSON null. It checks the enabled registration, resource binding, session absolute expiry, namespace epoch and revocation. This scry is an authorization fact, not a secret bearer credential: local agents already execute inside the ship's trust boundary. Every resource operation must check it and enforce its own scopes. A resource must not treat an old cached grant as current authorization.

For logout, reuse detection or abandoned exchanges, the owning resource sends `%connect-revoke` with `[resource=@tas session=@t]`. Connect checks kernel caller provenance and that the session belongs to that resource before deleting it. An absent session is an idempotent no-op. A resource cannot revoke another resource's or a document client's grant.

The resource owns its wire protocol, encryption envelopes, tokens, retries, storage limits and HTTP responses. Resource grants never authorize Connect document routes. The generic implementation contains no Bitwarden client IDs, scopes, JWT claims or timing exceptions. The separate [Bitwarden adapter](../integrations/bitwarden/README.md) illustrates that boundary. [grant-probe](../integrations/grant-probe/desk/app/grant-probe.hoon) is a second, unrelated notes-resource test consumer.

Durable state version 2 appends the integration-policy map. Version 0 and version 1 states migrate without changing existing clients or documents. The source change does not qualify a new alpha release; existing release gates remain open.
