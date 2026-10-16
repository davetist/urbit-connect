# iOS consent layout correction — 2026-10-16

The approval and denial buttons now remain inside the visible browser area at default page scale. Consent uses a bounded dynamic viewport height and bottom safe-area padding; all request details remain available in their own keyboard-focusable scroll region. The change is confined to the consent screen and does not change authorization decisions, scopes, callback handling or the setup/login cards.

Before the change, a normal 402×620 viewport placed the decision row at y602–644: its lower portion and center hit target fell outside the visible area. Smaller screens and long unbroken labels worsened the overflow. The old centered card had a minimum-height stage but no upper bound.

The new regression exercises the actual frontend and CSS with synthetic owner API responses. It checks geometry and hit testing before any automatic scrolling, at widths 320/375/402/430, in landscape, after viewport shrinkage, and with long labels/scopes. All six Chromium baseline cases failed; all twelve Chromium/WebKit cases passed after the fix. This browser-engine test is separate from native SSO evidence. Run `npm --prefix web run test:layout`; setup now installs the required engines, and full acceptance/qualification includes this suite.

The unchanged official Bitwarden iOS 2026.9.1 (3533) source build was installed in a new dedicated iOS 26.5 iPhone 17 Pro Simulator. Its actual system sign-in browser displayed both buttons above the toolbar without changing page scale. A native upward gesture revealed the final permission paragraph while the decisions stayed visible. Approve completed the normal callback; local unlock and automatic initial sync displayed all four existing synthetic records. No App Store or physical-device claim is made.

Evidence: [native result](../artifacts/consent-fix-2026-10-16/ios-results.json), [initial viewport](../artifacts/consent-fix-2026-10-16/ios-consent-default-scale.png), [scrolled details](../artifacts/consent-fix-2026-10-16/ios-consent-details-scrolled.png), [unlocked vault](../artifacts/consent-fix-2026-10-16/ios-unlocked-after-default-consent.png), and [complete Connect checks](../artifacts/consent-fix-2026-10-16/check-summary.json).

The disposable Simulator and its certificate trust were removed afterward. Existing Connect fixtures and real ships were preserved. The separate CLI first-sign-in failure and broader alpha qualification gates are not closed by this layout repair.
