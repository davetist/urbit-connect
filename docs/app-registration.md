# Registering an app on your ship

Open your ship’s HTTPS `/apps/connect/` page, log in to the ship, and choose **Register an app**. Registration is separate from consent: the next connection still opens the ship’s approval page. No Connect staff enrollment or publisher service is required.

The developer supplies:

| Field | Required value |
|---|---|
| Display name | A nonempty UTF-8 label of at most 80 bytes |
| Client ID | Starts with a lowercase ASCII letter; up to 48 lowercase letters, digits or hyphens |
| Exact callback URI | The app’s registered HTTPS or dotted custom-scheme callback, at most 256 bytes, with no query, fragment, user information or whitespace |
| Permissions | Each session explicitly requests read, write and/or delete on its server-assigned app space |

For the included Todo source use `connect-todo-prototype`, `Connect Todo`, and `org.example.urbitconnect.todo:/oauth/callback`. Register the sample explicitly; a fresh desk does not contain a pre-approved app.

The labels and public client ID are **unverified**. They do not authenticate the native publisher. Custom schemes can collide; PKCE binds an intercepted code to its initiating flow, but cannot prove which binary initiated a separate flow. Register known apps using instructions you trust. Connect does not fetch a publisher-supplied URL or use a client secret to claim native publisher authentication.

Only the authenticated ship owner can register, rename, disable, remove or revoke. Revoking keeps documents; disabling also prevents new sessions. Removal erases live documents and frees a slot after confirmation. Re-registering an ID creates a fresh namespace. Logical deletion leaves historical pier events and backups intact.

Eight registrations and 32 sessions are the current limits. Owner codes and browser cookies remain on the ship’s browser authentication boundary; never put them in SDK configuration, app source, a bug report or a release archive.

## Opt-in local resources

See [local resource integrations](resource-integrations.md) for immutable owner policies, exact loopback callbacks, authenticated Gall exchange/revoke and live grant checks. Resource scopes do not authorize document routes. Client-specific tokens and compatibility behavior live in separate resource desks. Existing document-client behavior and refresh-reuse policy remain unchanged.
