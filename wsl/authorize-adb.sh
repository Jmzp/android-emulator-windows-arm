#!/usr/bin/env bash
# Adds an adb public key to Android's trusted keys so `adb connect` works
# without clicking "Allow USB debugging" in the Android window.
#
#   ./authorize-adb.sh /mnt/c/Users/<you>/.android/adbkey.pub
set -euo pipefail

KEY_FILE="$1"
KEY="$(tr -d '\r\n' < "$KEY_FILE")"
[ -n "$KEY" ] || { echo "Empty key file: $KEY_FILE" >&2; exit 1; }

if sudo waydroid shell -- cat /data/misc/adb/adb_keys 2>/dev/null | grep -qF "$KEY"; then
  exit 0
fi
# The key contains spaces and base64 only, so single quotes are safe.
sudo waydroid shell -- sh -c "echo '$KEY' >> /data/misc/adb/adb_keys && chown system:shell /data/misc/adb/adb_keys && chmod 640 /data/misc/adb/adb_keys"
# adbd only reads adb_keys when a connection starts; restart to be safe.
sudo waydroid shell -- sh -c 'setprop ctl.restart adbd' || true
echo "adb key authorized."
