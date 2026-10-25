#!/usr/bin/env bash
# Stops the Android session, its window and the adb bridge.
set -uo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
UNITS=(waydroid-adb-bridge waydroid-emu-console waydroid-ui waydroid-session waydroid-weston)
systemctl --user stop waydroid-adb-bridge waydroid-emu-console waydroid-ui 2>/dev/null
waydroid session stop 2>/dev/null
systemctl --user stop "${UNITS[@]}" 2>/dev/null
systemctl --user reset-failed "${UNITS[@]}" 2>/dev/null
echo "Android stopped."
