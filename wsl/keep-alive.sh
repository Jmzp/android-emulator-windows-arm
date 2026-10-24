#!/usr/bin/env bash
# Keeps the distro running while Android's window is open.
# With systemd, WSL shuts a distro down once no wsl.exe client is attached;
# android.ps1 runs this script as that client. It exits when the given unit
# stops (e.g. the user closed the window), letting WSL release its memory.
#
#   ./keep-alive.sh <systemd-user-unit>
set -uo pipefail

UNIT="${1:-waydroid-weston}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Wait for start-android.sh to bring the unit up.
for _ in $(seq 1 180); do systemctl --user is-active -q "$UNIT" && break; sleep 1; done

while systemctl --user is-active -q "$UNIT"; do sleep 3; done
