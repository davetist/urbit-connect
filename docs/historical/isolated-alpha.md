# Historical isolated alpha walkthrough

This preserves the former README fixture walkthrough as historical documentation. It is not the default installation path or authorization to create fake ships, run synthetic tests or launch soak workloads. The owner's continuing direction defaults to static/build review and separately authorized actual official-client workflows; synthetic work requires an explicit change of that direction. Use [install](../install.md), [update](../update.md) and [current status](../current-readiness.md) for current guidance.

## Former fixture walkthrough

The reproducible development setup targets Apple Silicon macOS with Xcode 26.6, its command-line tools, Python 3.10+, Node 22.12+ and npm, and Homebrew. It downloads the pinned Vere 4.6 runtime, kernel-408 pill, Caddy, and iOS 26.5 Simulator runtime when missing. Allow roughly 15–20 GB for the runtime, Simulator, fake piers, and build products.

```sh
python3 scripts/setup.py --install-tools
```

Setup creates an owned `.work/alpha` fixture and dedicated **Connect Alpha** Simulators. Its local certificate is trusted only in those Simulators and the project’s Firefox profile. An existing demo is preserved. No production ship, global certificate store, Apple account, or paid service is needed.

To use it yourself, open `examples/ios-todo/ConnectTodo.xcodeproj`, select the `ConnectTodo` scheme and dedicated Simulator, and run. Enter the HTTPS address printed by setup, tap **Connect with Urbit**, log in to the fake ship in the system browser, and approve. Ports are bound to the checkout by `.work/alpha/targets.json`. The disposable owner login code is in the private `.work/alpha/dev/auth.json` file; do not put it in app configuration or source control. Run `python3 scripts/open_owner_ui.py` to open the manager in the dedicated Firefox profile. Normal host browsers deliberately do not trust the test certificate.

Create **Personal**, add **Buy milk**, and wait for **Saved on your ship**. That status means the ship acknowledged the write; queued offline edits have a different status. A conflicting edit keeps both versions for an explicit decision.

Build and package local source artifacts without starting acceptance or soak workloads:

```sh
python3 scripts/release_check.py --build
python3 scripts/release_check.py --verify release/manifest.json
```

The local desk archive is `dist/connect-0.2.0-alpha.1.tgz`, with a SHA-256 sidecar and file manifest. `scripts/release_check.py --build` also creates SDK, Todo source and complete-source archives twice and compares their hashes. See [development](../development.md) for check prerequisites, [install](../install.md) and [update](../update.md) for real ships, [operations](../operations.md) for restore, and [security](../security.md) for the trust model. Owner registration is local to the ship; registering Todo is an explicit sample option.
