# Canon PIXMA MG6250 — network scanning on current macOS

**Runs on:** the always-on Mac mini.
**Result:** the MG6250 appears as a scanner on every Mac and iOS device on the LAN,
with nothing installed on those devices.

No driver is written here. The printer already speaks two protocols that
open-source software understands; the job is wiring them up.

## Why this is needed

| | |
|---|---|
| **Printing** | Already works, and always did. The MG6250 shipped with AirPrint in 2011, so macOS talks to it over IPP with no driver. Nothing in this directory affects printing. |
| **Scanning** | Broken because Apple removed the bundled Canon ICA plugins, *and* the MG6250 predates eSCL/AirScan — so there is nothing for Image Capture to discover. Canon's own macOS software is long out of support. |

The fix has two halves:

1. **SANE's `pixma` backend** speaks Canon's own **BJNP** protocol over the network
   (port 8612). It has supported the MG6250 since pixma 0.17.0. Network-only here,
   which conveniently sidesteps the macOS USB sandbox problems that make USB
   scanning on modern macOS painful.
2. **AirSane** takes that SANE device and re-publishes it over mDNS as an
   **eSCL/AirScan** scanner. Macs, iPhones and iPads then discover it natively.

Net effect: the printer gains the AirPrint-scan support it was a few years too
early to ship with.

## Install

```bash
./setup-mg6250-airsane.sh
```

Have the printer powered on and awake first. The script will:

- install `sane-backends`, `jpeg`, `libpng`, `cmake` via Homebrew (no-ops if present)
- ensure the `pixma` backend is enabled in `dll.conf`
- broadcast for the printer and show what it found
- build and install AirSane (no Homebrew formula exists, so it compiles from source)
- apply the macOS gamma correction (0.5555 — otherwise scans come out dark)
- install and start a LaunchDaemon so it survives reboots

Two prompts must be answered correctly:

- **sudo password** — for `make install` and loading the daemon.
- **"allow airsaned to accept incoming network connections"** — click **Allow**.
  Deny this and no other device will see the scanner.

### If discovery fails

Find the IP on the printer's panel (**Setup ▸ Device settings ▸ LAN settings**):

```bash
./setup-mg6250-airsane.sh --ip 192.168.1.50
```

That pins `bjnp://<ip>` into `pixma.conf` instead of relying on broadcast. Give the
printer a DHCP reservation on the router so the address can't move — and keep the
real address out of this repo, which is public.

To test discovery without changing anything:

```bash
./setup-mg6250-airsane.sh --detect-only
```

Discovery failing almost always means one of: printer asleep, the mini is on a
different subnet or a guest SSID, or the router has client/AP isolation enabled.

## Using it

- **Web UI** — `http://localhost:8090/` on the mini, or
  `http://<mini-name>.local:8090/` from any browser on the network.
- **Any Mac** — appears in Printers & Scanners as a *Bonjour Scanner*. Use Image
  Capture or Preview; multi-page PDF and OCR are handled there, so no custom
  script is needed for them.
- **iPhone / iPad** — Notes ▸ Scan Documents, or the Files share sheet.

### Scanning part of the platen, not all of it

The default scan view only does the full platen. To select a region:

1. **Show Details** — bottom right of the Preview or Image Capture scan window.
   The simple view has no region option at all, which is why this looks missing.
2. **Overview** — runs a fast, low-resolution pass of the whole platen.
3. **Drag a marquee** over the area you want. Once drawn, its bounds are editable
   numerically, for when you need repeatable dimensions rather than eyeballing it.
4. Set resolution and format, then **Scan**.

The region goes to AirSane as eSCL scan geometry, so the crop happens at the
scanner rather than being thrown away afterwards. Selecting a small region and
*then* raising DPI is the right way to scan photos: resolution where it matters,
without a full-platen file to match.

**Detect Separate Items**, in the same detail pane, auto-crops several photos laid
on the platen into individual files — usually better than drawing marquees by hand.

The web UI on port 8090 exposes scan area numerically, which is the route to take
if a fixed region ever needs scripting.

## Operational notes

AirSane must be running for anyone to scan, which is why this lives on the mini
rather than on a laptop. Two things to keep true:

- **The mini must not sleep.** Check System Settings ▸ Energy. Disk sleep is fine;
  system sleep is not.
- **Re-run the setup script after a major macOS upgrade.** OS upgrades can break
  the Homebrew build or unload third-party LaunchDaemons. The script is idempotent,
  so re-running it is the repair procedure.

If this ever needs to move off the mini, a Raspberry Pi is the usual home: on
Raspberry Pi OS it's `apt install sane-utils`, then AirSane built the same way,
with config at `/etc/airsane/options.conf` and `/etc/default/airsane`. The
printer-side setup is identical, because BJNP does not care what is talking to it.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `scanimage -L` finds nothing | Printer asleep; wrong subnet; AP isolation; `pixma` commented out in `$(brew --prefix)/etc/sane.d/dll.conf` |
| AirSane web UI lists no scanner | AirSane only exports what `scanimage -L` sees — fix that first. Also check `LOCAL_SCANNERS_ONLY` is **false**: the MG6250 is a *network* SANE device and that setting would filter it out. |
| Scanner invisible to other devices | The network-access prompt was denied. Re-add `airsaned` under System Settings ▸ Network ▸ Firewall. |
| Image Capture error **21345** | mDNS/IPv6 issue. Enable IPv6 on the LAN, then reboot the mini. |
| Scans too dark | Gamma. Adjust `gray-gamma` / `color-gamma` in `options.conf`; 0.5555 is the starting point. |
| Verbose logs | `sudo launchctl bootout system /Library/LaunchDaemons/org.simulpiscator.airsaned.plist`, then `sudo airsaned --debug=true --access-log=-` in the foreground. |

## Uninstall

```bash
sudo launchctl bootout system /Library/LaunchDaemons/org.simulpiscator.airsaned.plist
sudo rm /Library/LaunchDaemons/org.simulpiscator.airsaned.plist
sudo rm -f "$(command -v airsaned)"
brew uninstall sane-backends       # optional
```

## Alternative considered

**VueScan** (~£50–100) supports the MG6250 on current macOS and is the usual
recommendation on Apple's forums for this printer. Rejected here because it is
per-machine: a licence and an install on every Mac, which is exactly what the
AirSane approach avoids.

## References

- [sane-pixma man page](https://www.mankier.com/5/sane-pixma) — BJNP/MFNP, ports, `pixma.conf`
- [AirSane](https://github.com/SimulPiscator/AirSane) and its [macOS notes](https://github.com/SimulPiscator/AirSane/blob/master/README.macOS.md)
- [Homebrew sane-backends](https://formulae.brew.sh/formula/sane-backends)
- [sane-pixma-macos](https://github.com/globe-teck/sane-pixma-macos) — fallback if the Homebrew build misbehaves
- [MG6250 on a current Mac](https://discussions.apple.com/thread/256249687)
