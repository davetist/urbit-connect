# Platform evidence

| Platform | Evidence and status |
|---|---|
| Apple Silicon macOS development | Pinned Vere 4.6/kernel 408, Xcode 26.6 (17F113), Node/npm and dedicated local fake ships; alpha rerun recorded separately |
| iPhone Simulator | Intended deployment floor iOS 18+; actual fixture runtime iOS 26.5 (23F77), iPhone 17 Pro and iPhone SE (3rd generation); inspect both final UI runs and screenshots |
| Linux ARM64/Pi-class real ship | Dedicated test comet, Pi 4 Model B Rev 1.4 / 8 GiB, aarch64 kernel 6.18.50+rpt-rpi-v8, Vere 4.6 / Zuse 408. Fresh install, 0.1→0.2 update, trusted HTTPS, resource bounds and packet-loss HTTP checks passed; these are historical observations, not requirements for a new timed/signoff qualification |
| Physical iPhone / TestFlight | Deferred; Simulator or deployment-target compilation is not physical-device/distribution evidence |
| Additional hosts/providers | Unqualified; custom desks, stable kernel/runtime, normal trusted HTTPS and adequate resources are prerequisites |

Real experiments must use an explicitly authorized, dedicated test ship; the mutating fake-ship harness must never target a real pier. A cloned real identity must remain isolated from Ames.

Resource guidance starts with the pinned local setup’s 15–20 GiB Mac allowance. The real-host report records measured RSS, allocated pier/event-log bytes and free space on the 8 GiB host. Those measurements are not demonstrated minimum disk/RAM requirements. The installer reserves at least 1 GiB plus twice the staged desk size; long-term retention still requires monitoring and verified backups.
