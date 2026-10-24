#!/usr/bin/env bash
# Starts the Waydroid session, opens the Android window through WSLg and
# exposes adbd on 0.0.0.0:$ADB_PORT so Windows can reach it.
#
#   ./start-android.sh [WIDTHxHEIGHT | full]
#
# By default Android runs inside a phone-sized nested Weston window
# (kiosk shell), because WSLg always maximizes Waydroid's own window.
# "full" skips Weston and uses the whole WSLg window instead.
set -euo pipefail

ADB_PORT="${ADB_PORT:-5555}"
WINDOW="${1:-432x936}"

# With systemd enabled, XDG_RUNTIME_DIR points at /run/user/$UID, which
# does not contain WSLg's Wayland/Pulse sockets. Link them in.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
for sock in wayland-0 wayland-0.lock pulse; do
  if [ -e "/mnt/wslg/runtime-dir/$sock" ] && [ ! -e "$XDG_RUNTIME_DIR/$sock" ]; then
    ln -s "/mnt/wslg/runtime-dir/$sock" "$XDG_RUNTIME_DIR/$sock"
  fi
done
if [ ! -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
  echo "No Wayland socket at $XDG_RUNTIME_DIR/wayland-0 (is WSLg enabled?)" >&2
  exit 1
fi

# Every long-running piece is a transient systemd user unit: a plain
# background process would die with the wsl.exe call that started it.
run_unit() {
  local unit="$1"; shift
  systemctl --user is-active -q "$unit" && return 0
  systemctl --user reset-failed "$unit" 2>/dev/null || true
  systemd-run --user --quiet --unit="$unit" --setenv=XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$@"
}

if [ "$WINDOW" = "full" ]; then
  DISPLAY_SOCKET=wayland-0
else
  DISPLAY_SOCKET=waydroid-0
  W="${WINDOW%x*}"; H="${WINDOW#*x}"
  echo "==> Opening phone window (${W}x${H})"
  run_unit waydroid-weston --setenv=WAYLAND_DISPLAY=wayland-0 \
    weston --backend=wayland --shell=kiosk --socket="$DISPLAY_SOCKET" \
           --width="$W" --height="$H" --idle-time=0
  for _ in $(seq 1 20); do [ -S "$XDG_RUNTIME_DIR/$DISPLAY_SOCKET" ] && break; sleep 0.5; done
  [ -S "$XDG_RUNTIME_DIR/$DISPLAY_SOCKET" ] || {
    echo "Weston did not start, see: journalctl --user -u waydroid-weston" >&2; exit 1; }
fi

sudo systemctl start waydroid-container

if ! waydroid status | grep -q "Session:.*RUNNING"; then
  echo "==> Starting Waydroid session"
  run_unit waydroid-session --setenv=WAYLAND_DISPLAY="$DISPLAY_SOCKET" waydroid session start
  for _ in $(seq 1 90); do
    waydroid status | grep -q "Session:.*RUNNING" && break
    sleep 1
  done
fi
waydroid status | grep -q "Session:.*RUNNING" || {
  echo "Session failed to start, see: journalctl --user -u waydroid-session" >&2; exit 1; }

echo "==> Showing Android"
run_unit waydroid-ui --setenv=WAYLAND_DISPLAY="$DISPLAY_SOCKET" waydroid show-full-ui

echo "==> Waiting for Android to boot"
booted() { [ "$(sudo waydroid shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; }
for _ in $(seq 1 180); do booted && break; sleep 1; done
booted || { echo "Android did not finish booting. Check: sudo waydroid logcat -b crash" >&2; exit 1; }

IP="$(waydroid status | awk -F'\t' '/IP address/ {print $NF}' | tr -d '[:space:]')"
case "$IP" in *.*.*.*) ;; *) IP=192.168.240.112 ;; esac

systemctl --user stop waydroid-adb-bridge 2>/dev/null || true
pkill -f "^socat TCP-LISTEN:${ADB_PORT}," 2>/dev/null || true  # stray bridge from a manual run
run_unit waydroid-adb-bridge socat "TCP-LISTEN:${ADB_PORT},fork,reuseaddr" "TCP:${IP}:5555"
echo "==> adb bridge: 0.0.0.0:${ADB_PORT} -> ${IP}:5555"
