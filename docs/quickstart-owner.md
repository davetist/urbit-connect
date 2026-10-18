# Owner quickstart

Prerequisites: a supported ship allowing custom desks; its backed-up pier; a reachable HTTPS origin with a valid certificate and renewal; and a compatible app with registration details supplied by its developer.

1. Follow `install.md` for the desk and HTTPS preflight. Real-host support remains pending until the named host profile has evidence in `artifacts/alpha/report.md`.
2. Visit `https://your-ship.example/apps/connect/`. Logged-out visitors go directly to the ship login before any Connect page or assets are served; the return URL preserves consent links. Log in as the local ship owner and configure that exact HTTPS origin. Copy the displayed base address. The SDK never receives the owner code or browser cookie.
3. Choose **Register an app** and enter the developer’s client ID and callback URI using the fields in `app-registration.md`. Registration does not grant a session.
4. Follow the app’s connection instructions using your ship’s base address. The app opens that ship’s login and consent page.
5. Read the app name, registration details and requested read/write/delete permissions; approve or deny on the ship. A fresh grant always asks for consent.
6. For document apps, save data in the app, then open the manager to inspect its documents. Review any conflicting edits deliberately. Resource apps manage their data in their own desk; Connect shows their access permissions and sessions.
7. Manage a session from the ship: rename or disable its registration, revoke one/all sessions while keeping documents, export data, or confirm erase/removal. Removal frees a slot and invalidates pending consent, sessions and the old namespace. Re-registration gets a fresh namespace.
