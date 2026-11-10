# macmini-services

Setup and configuration for the always-on Mac mini.

This machine is the household's always-on host: anything that needs to be running
when nobody is at a keyboard lives here. This repo is the record of how it is put
together — not application code, which lives in its own repos.

Private on purpose. It accumulates LAN addresses, hostnames and machine layout.

## Contents

| Directory | What it covers |
|---|---|
| [`printer-scanner/`](printer-scanner/) | Canon PIXMA MG6250 re-published to the network as an AirScan scanner, so every Mac and iOS device can scan to it |

## Services running on this machine

An index, so there's one place that lists what the mini is responsible for.

- **HiddenHelp Telegram scripts** — code lives in [`hiddenhelpbots`](https://github.com/richardmpreston/hiddenhelpbots), not duplicated here.
- **AirSane** — network scanner bridge for the MG6250. LaunchDaemon at
  `/Library/LaunchDaemons/org.simulpiscator.airsaned.plist`, web UI on port 8090.
  See [`printer-scanner/`](printer-scanner/).

## Conventions

- Setup scripts are **idempotent** — safe to re-run, and re-running is the
  intended way to repair a service after an OS upgrade.
- Anything installed as a LaunchDaemon or LaunchAgent has its plist path recorded
  in the relevant README, so it can be found and unloaded later.
- Each service gets a directory with its own README explaining *why*, not just how.
  Future-you will not remember why BJNP was involved.
