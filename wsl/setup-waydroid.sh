#!/usr/bin/env bash
# Installs and initializes Waydroid inside the Ubuntu WSL distro.
# Run as your normal (non-root) user once the binder kernel is active.
#
#   ./setup-waydroid.sh [VANILLA|GAPPS|KEEP] [OWNER/REPO]
#
# VANILLA: plain LineageOS, install Expo Go / your APKs with adb.
# GAPPS: includes Play Store and Play services (needs device registration).
# KEEP (default): keep the image type already installed, VANILLA on a new
# install. Switching types keeps Android's apps and data.
# OWNER/REPO: GitHub repo whose `ota` branch mirrors the images (see
# install-images.py); "official" skips the mirror.
set -euo pipefail

SYSTEM_TYPE="${1:-KEEP}"
[ "$SYSTEM_TYPE" = KEEP ] && SYSTEM_TYPE=""
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
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates socat adb python3 weston zstd aria2
# start-android.sh builds the shared clipboard (a Weston module) with these.
LIBWESTON_DEV="$(dpkg-query -W -f='${Package}\n' 'libweston-*-0' 2>/dev/null | sed -n 's/-0$/-dev/p' | head -1)"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc libc6-dev pkg-config ${LIBWESTON_DEV:+"$LIBWESTON_DEV"}

if ! command -v waydroid >/dev/null; then
  echo "==> Adding Waydroid repository"
  curl -fsSL https://repo.waydro.id | sudo bash
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq waydroid
fi

# The image type in use, from the channel file waydroid.cfg points at.
CURRENT="$(sed -n 's#^system_ota = .*/\([A-Z_]*\)\.json$#\1#p' /var/lib/waydroid/waydroid.cfg 2>/dev/null || true)"
if [ -f /var/lib/waydroid/waydroid.cfg ] && [ -z "$CURRENT" ] && [ -z "$SYSTEM_TYPE" ]; then
  echo "==> Keeping the existing Android images (not from an OTA channel)"
else
  SYSTEM_TYPE="${SYSTEM_TYPE:-${CURRENT:-VANILLA}}"
  if [ "$SYSTEM_TYPE" != "$CURRENT" ]; then
    if waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; then
      echo "Android is running; stop it before switching images." >&2
      exit 1
    fi
    if [ -n "$CURRENT" ]; then
      echo "==> Switching Android from $CURRENT to $SYSTEM_TYPE (installed apps and data are kept)"
    else
      echo "==> Installing Android images ($SYSTEM_TYPE)"
    fi
    python3 "$(dirname "$(readlink -f "$0")")/install-images.py" "$SYSTEM_TYPE" "$MIRROR_REPO"
  fi
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
