#!/bin/bash
#
# Canon PIXMA MG6250 -> network scanner for every Mac/iPhone on the LAN.
#
# Installs the SANE "pixma" backend (talks Canon's BJNP protocol over the
# network, no vendor driver) and AirSane (re-publishes it over mDNS as an
# eSCL/AirScan device, so Image Capture / Preview / iOS discover it natively).
#
# Target: Apple Silicon macOS with Homebrew already installed.
#
# Usage:
#   ./setup-mg6250-airsane.sh                 # autodiscover the printer
#   ./setup-mg6250-airsane.sh --ip 192.168.1.50   # pin the IP if discovery fails
#   ./setup-mg6250-airsane.sh --detect-only       # just look for the scanner, change nothing
#
# Re-running is safe; every step is idempotent.

set -euo pipefail

PRINTER_IP=""
DETECT_ONLY=0
SRC_DIR="${AIRSANE_SRC:-$HOME/src}"
PLIST="/Library/LaunchDaemons/org.simulpiscator.airsaned.plist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) PRINTER_IP="${2:-}"; shift 2 ;;
    --detect-only) DETECT_ONLY=1; shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight

say "Checking prerequisites"

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."
command -v brew >/dev/null 2>&1 || die "Homebrew not found on PATH. Install it from https://brew.sh first."

BREW_PREFIX="$(brew --prefix)"
SANE_DIR="$BREW_PREFIX/etc/sane.d"
note "Architecture:    $(uname -m)"
note "Homebrew prefix: $BREW_PREFIX"

# ------------------------------------------------------------ sane-backends

if [[ $DETECT_ONLY -eq 0 ]]; then
  say "Installing SANE and build tools (Homebrew)"
  note "This is a no-op for anything already installed."
  brew install sane-backends jpeg libpng cmake
else
  command -v scanimage >/dev/null 2>&1 \
    || die "scanimage not found. Run without --detect-only first to install sane-backends."
fi

# Make sure the pixma backend is enabled. Homebrew ships dll.conf with all
# backends listed; a stray '#' in front of pixma is the classic silent failure.
if [[ -f "$SANE_DIR/dll.conf" ]]; then
  if grep -Eq '^[[:space:]]*pixma[[:space:]]*$' "$SANE_DIR/dll.conf"; then
    note "pixma backend already enabled in dll.conf"
  else
    if [[ $DETECT_ONLY -eq 1 ]]; then
      note "WARNING: pixma is not enabled in $SANE_DIR/dll.conf"
    else
      say "Enabling the pixma backend"
      # Uncomment it if present-but-commented, otherwise append it.
      if grep -Eq '^[[:space:]]*#[[:space:]]*pixma[[:space:]]*$' "$SANE_DIR/dll.conf"; then
        sed -i '' -E 's/^[[:space:]]*#[[:space:]]*pixma[[:space:]]*$/pixma/' "$SANE_DIR/dll.conf"
        note "Uncommented 'pixma' in $SANE_DIR/dll.conf"
      else
        printf 'pixma\n' >> "$SANE_DIR/dll.conf"
        note "Appended 'pixma' to $SANE_DIR/dll.conf"
      fi
    fi
  fi
else
  note "No dll.conf at $SANE_DIR/dll.conf (unexpected, continuing anyway)"
fi

# --------------------------------------------------------- pin the IP if given

if [[ -n "$PRINTER_IP" && $DETECT_ONLY -eq 0 ]]; then
  say "Pinning the printer at $PRINTER_IP"
  mkdir -p "$SANE_DIR"
  touch "$SANE_DIR/pixma.conf"
  if grep -q "bjnp://$PRINTER_IP" "$SANE_DIR/pixma.conf"; then
    note "Already present in pixma.conf"
  else
    printf 'bjnp://%s\n' "$PRINTER_IP" >> "$SANE_DIR/pixma.conf"
    note "Added 'bjnp://$PRINTER_IP' to $SANE_DIR/pixma.conf"
  fi
fi

# -------------------------------------------------------------- find the thing

say "Looking for the scanner"
note "Broadcast discovery on the local subnet. Give it a few seconds."
note "macOS may now ask to allow network access - click Allow."
echo

set +e
SCAN_LIST="$(scanimage -L 2>&1)"
set -e
echo "$SCAN_LIST" | sed 's/^/    /'
echo

if echo "$SCAN_LIST" | grep -qi 'pixma'; then
  note "Found a PIXMA device. Good."
else
  echo
  note "No PIXMA device found. Before going further, check:"
  note "  1. The printer is powered on and awake (it must be, not just plugged in)."
  note "  2. The Mac and printer are on the SAME subnet - not a guest network,"
  note "     and the router does not have client/AP isolation enabled."
  note "  3. If you know the printer's IP, re-run with: --ip <address>"
  note "     Find it on the printer: Setup > Device settings > LAN settings."
  if [[ $DETECT_ONLY -eq 0 ]]; then
    echo
    read -r -p "    Carry on and install AirSane anyway? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || die "Stopped. Fix discovery first, then re-run."
  fi
fi

if [[ $DETECT_ONLY -eq 1 ]]; then
  say "Detect-only mode: nothing was installed or changed beyond Homebrew packages"
  exit 0
fi

# ------------------------------------------------------------------- AirSane

say "Building AirSane from source"
note "There is no Homebrew formula for it, so this clones and compiles."

mkdir -p "$SRC_DIR"
if [[ -d "$SRC_DIR/AirSane/.git" ]]; then
  note "Updating existing checkout at $SRC_DIR/AirSane"
  git -C "$SRC_DIR/AirSane" pull --ff-only
else
  git clone https://github.com/SimulPiscator/AirSane.git "$SRC_DIR/AirSane"
fi

rm -rf "$SRC_DIR/AirSane-build"
mkdir -p "$SRC_DIR/AirSane-build"
cd "$SRC_DIR/AirSane-build"
cmake "$SRC_DIR/AirSane"
make

say "Installing AirSane (needs sudo)"
note "Installs the binary and a system LaunchDaemon so it starts at boot."
sudo make install

# ------------------------------------------------------------------- gamma fix

# macOS renders scans assuming ~gamma 1.8, so untouched scans come out dark.
# AirSane's own README recommends ~0.5555 to compensate.
for candidate in /etc/airsane "$BREW_PREFIX/etc/airsane" /usr/local/etc/airsane; do
  if [[ -d "$candidate" ]]; then
    if [[ -f "$candidate/options.conf" ]] && grep -q 'gray-gamma' "$candidate/options.conf"; then
      note "Gamma already configured in $candidate/options.conf"
    else
      say "Applying the macOS gamma correction"
      printf '\n# Added by setup-mg6250-airsane.sh: macOS assumes ~gamma 1.8\ndevice full\ngray-gamma 0.555555\ncolor-gamma 0.555555\n' \
        | sudo tee -a "$candidate/options.conf" >/dev/null
      note "Wrote gray-gamma/color-gamma to $candidate/options.conf"
    fi
    break
  fi
done

# ------------------------------------------------------------- start the daemon

say "Starting the AirSane daemon"
note "macOS will ask whether to allow 'airsaned' to accept network connections."
note "You MUST click Allow, or other devices will not see the scanner."

if [[ ! -f "$PLIST" ]]; then
  die "Expected the LaunchDaemon at $PLIST but it is not there. Check the 'make install' output above."
fi

# bootstrap is the modern form; load -w still works on older releases.
if ! sudo launchctl bootstrap system "$PLIST" 2>/dev/null; then
  sudo launchctl load -w "$PLIST" 2>/dev/null || note "Daemon appears to be loaded already."
fi

sleep 3

say "Done"
cat <<EOF

    Check it worked, in this order:

    1. Web interface:   http://localhost:8090/
       The MG6250 should be listed. You can scan from here directly,
       and from any browser on the network using this Mac's name.

    2. This Mac:        System Settings > Printers & Scanners
       The scanner appears as a "Bonjour Scanner". Open Image Capture
       and scan once - multi-page PDF and OCR are handled there.

    3. Other devices:   iPhone/iPad - Notes > Scan Documents, or the
       share sheet. Other Macs - Image Capture, no setup needed.

    IMPORTANT: this Mac must be awake for anyone to scan. If it is a laptop
    that sleeps or travels, see the README about moving AirSane to a
    Raspberry Pi. The configuration is identical.

    Troubleshooting:
      Logs:        sudo launchctl print system/org.simulpiscator.airsaned
      Foreground:  sudo airsaned --debug=true --access-log=-
      Stop:        sudo launchctl bootout system $PLIST
      Error 21345 in Image Capture: enable IPv6 on your network, then
        reboot this Mac. It is an mDNS/IPv6 issue, not a scanner fault.

EOF
