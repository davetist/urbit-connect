# Trust and authority

The user trusts the ship process, its host/operator, and the explicitly paired HTTPS endpoint. Documents are readable on the ship. Standard TLS protects traffic only to its termination point; a reverse proxy is part of the trusted endpoint. This is not host-blind end-to-end encryption or a guarantee against a malicious application, phone OS, or ship operator.

## App and owner separation

The native SDK is a public client using system-browser approval, random state, PKCE S256, a single-use 60-second authorization code, 10-minute access tokens, and a rotating refresh family with a 30-day absolute lifetime. A replayed consumed refresh token revokes that family. The SDK records refresh intent durably; a lost refresh response requires reauthorization instead of retrying the old token. Callback URI, client, state, issuer and instance are checked. The SDK’s URLSession carries no owner cookie and rejects cross-origin redirects.

The owner interface requires actual authenticated local Eyre authority. A local HTTP delivery alone and an authenticated visitor from another ship are insufficient. Owner writes also require exact origin and a cookie-bound CSRF token. Eight owner contexts are retained; opening another authenticated context evicts the oldest, requiring that older page to reload. App bearer credentials never authorize owner operations.

Client registrations are owner-managed and their publisher labels are unverified. Each registration gets a server-selected namespace. App payloads cannot choose another namespace or forward arbitrary Gall pokes/scries. HTTP response subscriptions are accepted only on the kernel-derived Eyre response duct; generic Gall/channel subscriptions are rejected. Incoming HTTP pokes must match that actual Eyre subscription. Reload drops transient response watches. Read/write/delete scopes are checked before mutations and receipt replay. Revocation is rechecked for pending polls, snapshots, refresh and normal requests.

## Storage and recovery

Authoritative records, mutation receipts, tombstones, client registrations and grants are versioned Gall state. Snapshots and pending polls are transient. An atomic batch gets one revision; compare-and-swap conflicts keep the client draft. Receipts recognize the exact request bytes for 30 days. Older offline mutations require review. Erasing a namespace rotates its epoch and revokes its sessions. Rolling back a pier requires owner restore-epoch rotation before reconnecting clients.

Access/refresh/code secrets are represented by hashes in the agent’s active grant state. Urbit event history may retain incoming headers, authorization inputs and older data: hashing active state does not make the pier or its backups secret-free. Protect the whole host/pier and its backups. Logical deletion and revocation do not securely erase history, downloaded copies, or old backups.

The SDK stores credentials in non-synchronizing, device-only Keychain items. Its SQLite cache/outbox uses transactional WAL/FULL persistence, protected files and backup exclusion. Revocation or unavailable credentials clears confirmed remote cache and retains recoverable unsent drafts. This does not promise forensic erasure of flash, SQLite history, or OS snapshots. A macOS consumer needs a correctly entitled app context for the data-protection Keychain.

## Resource bounds and delivery

See [capacity.md](capacity.md) for retained parser, concurrency, credential-lifetime, replay-history and rate controls, with their reasons. Product document/storage/app/session/outbox quotas are removed. All document/auth responses use no-store. The owner bundle uses same-origin assets with restrictive response headers and text-safe DOM rendering. There are no third-party analytics or a developer data backend in this implementation.

This is a local prototype, not a production security certification. The acceptance report distinguishes pure handler tests, actual HTTP/Gall behavior, and native UI evidence. App attestation, universal-link deployment, independent ship identity verification, background push, arbitrary queries, attachment storage and host-blind encryption are outside this version.

## Opt-in local resources

See [local resource integrations](resource-integrations.md) for immutable owner policies, exact loopback callbacks, authenticated Gall exchange/revoke and live grant checks. Resource scopes do not authorize document routes. Client-specific tokens and compatibility behavior live in separate resource desks. Existing document-client behavior and refresh-reuse policy remain unchanged.
