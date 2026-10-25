#!/usr/bin/env bash
# Installs and initializes Waydroid inside the Ubuntu WSL distro.
# Run as your normal (non-root) user once the binder kernel is active.
#
#   ./setup-waydroid.sh [VANILLA|GAPPS] [OWNER/REPO]
#
# VANILLA (default): plain LineageOS, install Expo Go / your APKs with adb.
# GAPPS: includes Play Store (needs device registration with Google).
# OWNER/REPO: GitHub repo whose `ota` branch mirrors the images (see
# .github/workflows/mirror-android-images.yml); "official" skips the mirror.
set -euo pipefail

SYSTEM_TYPE="${1:-VANILLA}"
MIRROR_REPO="${2:-Jmzp/android-emulator-windows-arm}"

if ! grep -q binder /proc/filesystems; then
  echo "binder is not available in this kernel ($(uname -r))." >&2
  echo "Build and install the custom kernel first (see README)." >&2
  exit 1
fi

if [ "$(cat /proc/1/comm)" != "systemd" ]; then
  echo "systemd is not PID 1. Add '[boot] systemd=true' to /etc/wsl.conf and run 'wsl --shutdown'." >&2
  exit 1
fi

echo "==> Installing dependencies"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates socat adb python3 weston zstd

if ! command -v waydroid >/dev/null; then
  echo "==> Adding Waydroid repository"
  curl -fsSL https://repo.waydro.id | sudo bash
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq waydroid
fi

if [ ! -f /var/lib/waydroid/waydroid.cfg ]; then
  # Waydroid's own images come from SourceForge, which can be very slow. The
  # mirror serves the same files (same SHA-256) from GitHub Releases. Use it
  # when it has this architecture and image type, else the official channel.
  SYSTEM_CHANNEL=https://ota.waydro.id/system
  VENDOR_CHANNEL=https://ota.waydro.id/vendor
  ARCH="$(python3 -c 'import sys; sys.path.insert(0, "/usr/lib/waydroid"); from tools.helpers import arch; print(arch.host())' 2>/dev/null || true)"
  MIRROR="https://raw.githubusercontent.com/$MIRROR_REPO/ota"
  if [ "$MIRROR_REPO" != official ] && [ -n "$ARCH" ] &&
     curl -fsI "$MIRROR/system/lineage/waydroid_$ARCH/$SYSTEM_TYPE.json" >/dev/null &&
     curl -fsI "$MIRROR/vendor/waydroid_$ARCH/MAINLINE.json" >/dev/null; then
    SYSTEM_CHANNEL="$MIRROR/system"
    VENDOR_CHANNEL="$MIRROR/vendor"
    echo "==> Downloading Android images ($SYSTEM_TYPE, $ARCH) from the GitHub mirror — ~1 GB"
  else
    echo "==> Downloading Android images ($SYSTEM_TYPE, ${ARCH:-arm64}) from SourceForge — ~1 GB, can be slow"
  fi
  sudo waydroid init -s "$SYSTEM_TYPE" -c "$SYSTEM_CHANNEL" -v "$VENDOR_CHANNEL"
fi

echo "==> Applying WSL-friendly properties"
# Software rendering is the safe default under WSLg; the host GPU is only
# exposed through D3D12 and Waydroid's Mesa doesn't ship that driver.
sudo python3 - <<'EOF'
import configparser
path = "/var/lib/waydroid/waydroid.cfg"
cfg = configparser.ConfigParser()
cfg.optionxform = str  # property names are case sensitive
cfg.read(path)
if not cfg.has_section("properties"):
    cfg.add_section("properties")
props = cfg["properties"]
props["ro.hardware.gralloc"] = "default"
props["ro.hardware.egl"] = "swiftshader"
props["persist.waydroid.multi_windows"] = "false"
# The window (nested Weston or WSLg) sets the size. A fixed width/height that
# doesn't match makes the compositor reject Waydroid's buffer and the
# hwcomposer crash.
for key in ("persist.waydroid.width", "persist.waydroid.height"):
    props.pop(key, None)
with open(path, "w") as f:
    cfg.write(f)
EOF
sudo waydroid upgrade --offline

sudo systemctl enable --now waydroid-container
# Lets start-android.sh run the session as a user unit that outlives the
# wsl.exe call that launched it.
sudo loginctl enable-linger "$USER"
echo "==> Waydroid ready. Start it with start-android.sh (or android.ps1 start from Windows)."
