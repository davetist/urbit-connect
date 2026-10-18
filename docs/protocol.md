# Connect protocol 1

The machine-readable route and shape contract is `protocol/v1/openapi.yaml` (JSON syntax, which is valid YAML). This document defines semantics shared by the ship, owner UI and Swift package. Fixtures under `protocol/v1/fixtures/` are development data only.

## Identity and transport

Pair an explicitly chosen HTTPS origin. Its issuer is that exact origin plus `/connect`. Protocol version, persistent random `instanceId`, ship display name and decimal `syncEpoch` come from `/connect/v1/info`. Cache accounts by issuer plus instance, never just the ship name. A configured endpoint proves authorization at that endpoint; it is not an independently verified Azimuth identity assertion. Reject cross-origin redirects, certificate errors, unexpected issuer/instance changes and unsupported major versions. The SDK's HTTP session is ephemeral and does not share browser cookies.

All API responses use `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, and no permissive CORS headers. Owner pages additionally use a restrictive CSP, `frame-ancestors 'none'`, `X-Frame-Options: DENY` and `Referrer-Policy: no-referrer`. Data never travels through a developer-operated backend. TLS terminators and the ship host are trusted.

## Authorization

Registered public clients use OAuth authorization code with PKCE S256, exact redirect matching and fresh state. There is no client secret or ID token. Authorization starts validate all parameters before any redirect; errors for unknown clients/redirects stay local. A valid start creates a five-minute pending consent and redirects to the local owner UI. GET never approves. Approval requires Eyre authentication for the local ship, a nonce identifying that pending request, a CSRF token bound to the browser's current cookie context, exact Origin, and POST. An EAuth visitor cannot approve.

The callback includes only a 60-second, single-use code and the original state (or the OAuth error and state for denial). The token endpoint accepts URL-encoded standard `authorization_code`/`refresh_token` grant bodies. Codes bind client, redirect, PKCE, scopes, namespace and namespace epoch. Access tokens last ten minutes. Refresh tokens rotate within an absolute 30-day session; reuse of a consumed refresh token revokes that session. An ambiguous refresh response requires reauthorization. Tokens are opaque entropy-derived secrets; the ship stores their SHA-256 digests and the SDK uses private device-only Keychain storage. Tokens never appear in query parameters or exports.

Scopes are `documents:read`, `documents:write` and `documents:delete`. Namespace selection comes exclusively from the verified session. Unknown JSON members, including `namespace`/`clientId` overrides on a mutation, are rejected. Replacing a document can remove nested fields regardless of document-delete scope. Every retry rechecks current permissions before accessing a receipt.

## Documents and mutations

A document is `{id,collection,data,revision,updatedAt}`. IDs are lower-case UUID strings; collection names match `[a-z][a-z0-9-]{0,47}`. `updatedAt` is a UTC RFC 3339 timestamp. Revisions and epochs are canonical unsigned decimal strings, never JSON numbers; their representation is exact above JavaScript's safe-integer limit. The ship rejects noncanonical leading zeros and signs.

`data` is an object in the portable JSON subset. The decoder rejects duplicate decoded keys, invalid UTF-8, unpaired surrogates, trailing content, U+0000, nonfinite numbers, absolute numeric values above 9007199254740991, exponent magnitude above 1024 and fractional components above 1024 digits, and numeric spellings above 2048 bytes. Numeric source spelling is preserved. Decoded keys compare by UTF-8 bytes; canonically equivalent Unicode spellings remain distinct. Document data has a maximum of 16 nested containers. Protocol, persistence and export envelopes have a separate 24-container ceiling so a valid document remains valid inside a mutation, snapshot, change batch or import. SDK encoding validates constructed values as well as received bytes. This deliberately excludes some otherwise valid JSON values rather than silently rounding or truncating them.

`POST /connect/v1/mutations` takes `{requestId,operations}`. Each operation has `type`, `collection`, `id`, `expectedRevision`, and `data` for `put`. Null expected revision means create-only; a prior revision means compare-and-swap. Delete requires a prior revision. Duplicate targets within a batch are invalid. The entire batch commits at one namespace revision or changes nothing. An update cannot resurrect a missing record. A retained tombstone also prevents reusing its ID with create-only.

A success contains `{revision,results}`; each compact result identifies its collection, ID, revision and deletion status. It does not contain document bodies. The receipt binds exact submitted bytes, request UUID, namespace, global epoch and namespace epoch. Repeating the exact request returns the same success; changed bytes return `idempotency_mismatch`. A new authorized session in the same epochs can recover the prior receipt. Clients persist exact bytes before sending and stop blindly retrying mutations older than the 30-day receipt window.

Errors use `{error:{code,message,requestId}}`, with an optional `retryAfterSeconds` field. This implementation supplies the `Retry-After` header: one second for an occupied long-poll slot, 60 seconds for other capacity/rate limits. A 409 `conflict` adds the target, current revision or tombstone revision, `deleted`, and `current` only for a read-authorized caller. The client preserves both the draft and current version. OAuth routes use standard OAuth error objects instead. Missing authority is 401; scope/owner denial 403; malformed input 400; missing document 404; stale sync state 410; transient-capacity/rate bounds 429 with Retry-After.

## Synchronization

A collection GET is ordered by document ID with limit 1–100 and an epoch-bound continuation. It is a live listing, not a consistent export.

`POST /snapshots` captures an immutable namespace view at a cursor and returns the first page. Subsequent pages refer to that snapshot ID and offset, are bound to its session, and never mix in later writes. Pages contain `{snapshotId,atCursor,documents,nextPage}`. The snapshot has a renewable 60-second inactivity lease. Each validated successful page renews it; an authenticated, authorized, unexpired continuation that is rate-limited receives the advertised 60-second wait plus that inactivity allowance. Invalid, expired, revoked or wrong-owner requests do not renew it. The SDK retains accumulated pages while waiting for a 429 continuation retry. Begin changes strictly after `atCursor` once all pages are durably installed in one local transaction. Clear transient snapshots and polls on agent reload.

`GET /changes?after=...&wait=25&limit=100` returns whole change batches, `nextCursor`, and `hasMore`. Cursors encode global epoch, namespace epoch and revision; clients treat them as opaque. A put change includes `document` and `deleted:false`; a delete includes collection, ID, revision and `deleted:true`. A 410 gap restarts a snapshot while retaining unsent drafts. A changed identity/restore epoch requires reauthorization. Authorization is rechecked at delivery, including a pending poll, snapshot page or receipt. Revocation preserves owner data and invalidates access promptly.

## Execution and retention controls

There are no product document-byte, request-byte, mutation-count, live-storage, registration or durable-session quotas. See [capacity.md](capacity.md) for the retained controls and concrete reasons: recursive JSON depth/numeric validity, canonical identifier grammar, finite response pages, transient authorization/snapshot/poll slots, request rates, credential lifetimes and replay-history retention. Pages continue until complete; a response page size is not a total-data ceiling.

Receipts and tombstones retain a 30-day recovery window with no count cap. Journal expiry requires a fresh snapshot and never removes live documents. Owner and app writes share validation, permission and atomic version checks. Erasing one namespace advances its epoch and revokes its sessions. Restoring an older pier requires explicit global restore-epoch rotation and reauthorization, since rollback cannot be inferred reliably from restored state alone.

Refresh families retain at most 4,096 consumed token hashes. Reaching this retained security-history boundary revokes that family and requires fresh owner-approved connection; consumed tokens are never silently forgotten while their family stays valid.

## Opt-in local resources

See [local resource integrations](resource-integrations.md) for immutable owner policies, exact loopback callbacks, authenticated Gall exchange/revoke and live grant checks. Resource scopes do not authorize document routes. Client-specific tokens and compatibility behavior live in separate resource desks. Existing document-client behavior and refresh-reuse policy remain unchanged.

## Client ID migration

`POST /connect/owner/v1/clients/{id}/rename` takes `{id: "new-id", confirmClientId: "old-id", confirmNamespace: "app-N"}` under the existing owner cookie, exact Origin and CSRF checks. The source ID and namespace must match, the destination must be a valid unused client ID, and a collision returns 409. A same-ID request is an authenticated no-op.

Renaming preserves the namespace, documents, enabled state, immutable resource policy, session IDs, token digests, expirations and pending authorization state. It changes client references atomically across registrations, sessions, pending consents, authorization codes and authorization-start counters. Callers must use the new ID for subsequent authorization/code exchanges and generic token refreshes; an application adapter can translate its external client IDs. Rename does not grant additional permissions or re-enable a disabled client.

For cleanup of unused registrations, the existing remove endpoint accepts optional `onlyUnused: true`. It atomically refuses deletion when a live session, unexpired consent/code or any document history exists. The existing confirmation fields remain required; omitting the option preserves explicit removal and revocation behavior.
