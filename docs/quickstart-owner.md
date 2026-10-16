# Owner quickstart

Prerequisites: a supported ship allowing custom desks; its backed-up pier; a reachable HTTPS origin with a valid certificate and renewal; and, for Todo, an Apple Silicon Mac with the pinned Xcode/Simulator toolchain. The Simulator/source deliverable needs no paid Apple membership. It is not an App Store or TestFlight download.

1. Follow `install.md` for the desk and HTTPS preflight. Real-host support remains pending until the named host profile has evidence in `artifacts/alpha/report.md`.
2. Visit `https://your-ship.example/apps/connect/`, log in to the ship and configure that exact HTTPS origin. Copy the displayed base address. The SDK never receives the owner code or browser cookie.
3. Register your known app using the fields in `app-registration.md`. Choose the explicit **Register Todo sample** option only when using the included example. Registration does not grant a session.
4. Build Todo from source using `development.md`. Enter the copied base address once. If you paste the known manager URL, confirm the offered base origin. The system browser opens that ship’s login and consent page.
5. Read the unverified app label and requested read/write/delete permissions; approve or deny on the ship. A fresh grant always asks for consent.
6. In Todo create **Personal**, add **Buy milk**, and wait for **Saved on your ship**. Offline edits have a pending/local status. Open the manager to inspect the same document. Review any conflicting edits deliberately.
7. Manage a session from the ship: rename or disable its registration, revoke one/all sessions while keeping documents, export data, or confirm erase/removal. Removal frees a slot and invalidates pending consent, sessions and the old namespace. Re-registration gets a fresh namespace.

Setup time and time to the first save are separate measurements. The ten-minute first-save target begins after the desk, sample registration and Simulator are ready. There is no required independent trial or timed readiness verdict.
