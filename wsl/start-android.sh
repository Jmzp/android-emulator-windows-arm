#!/usr/bin/env bash
# Starts the Waydroid session, opens the Android window through WSLg and
# exposes adbd (and a minimal emulator console) so Windows adb lists it as
# emulator-<ADB_PORT - 1>.
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

HERE="$(dirname "$(readlink -f "$0")")"
# Copies of repo files live here: socat's EXEC and weston's --modules can't
# take a path with spaces (a repo under "C:\Users\First Last").
SHARE="$HOME/.local/share/android-wsl"

# Builds the Weston clipboard module when it's missing or its source changed.
# setup-waydroid.sh installs the compiler and libweston headers.
build_clipboard_bridge() {
  local src="$HERE/clipboard/clipboard-bridge.c" so="$SHARE/clipboard-bridge.so" lib
  install -D -m 644 "$HERE/clipboard/windows-clipboard.py" "$SHARE/windows-clipboard.py"
  if [ ! -f "$so" ] || ! cmp -s "$src" "$SHARE/clipboard-bridge.c"; then
    lib="$(pkg-config --list-all 2>/dev/null | grep -o '^libweston-[0-9]*' | head -1)"
    if [ -z "$lib" ] || ! command -v gcc >/dev/null; then
      echo "==> Shared clipboard unavailable: run 'android.ps1 setup' once to enable it" >&2
      return 1
    fi
    # shellcheck disable=SC2046  # pkg-config prints several flags
    gcc -shared -fPIC -O2 -o "$so" "$src" $(pkg-config --cflags --libs "$lib") || {
      echo "==> Could not build the clipboard module; continuing without it" >&2
      rm -f "$so"; return 1; }
    cp "$src" "$SHARE/clipboard-bridge.c"
  fi
}

# Weston's Wayland backend titles its window "Weston Compositor - wayland0",
# both in the frame it draws and in Windows' taskbar. Keep a copy of the
# backend whose title reads "Android Emulator" (same-length strings, so the
# library is otherwise untouched); WESTON_MODULE_MAP makes Weston load it.
# Prints the WESTON_MODULE_MAP entry, or nothing if the strings don't match.
patch_weston_title() {
  local lib copy="$SHARE/wayland-backend.so"
  lib="$(find /usr/lib -path '*libweston-*/wayland-backend.so' 2>/dev/null | head -1)"
  [ -n "$lib" ] || return 0
  mkdir -p "$SHARE"
  if [ ! -f "$copy" ] || [ "$lib" -nt "$copy" ]; then
    python3 - "$lib" "$copy" <<'EOF' || return 0
import sys
data = open(sys.argv[1], "rb").read()
# The title is asprintf("%s - %s", "Weston Compositor", output name).
swaps = [(b"Weston Compositor\0", b"Android Emulator\0\0"), (b"%s - %s\0", b"%s\0- %s\0")]
for old, new in swaps:
    if data.count(old) != 1:
        sys.exit(1)
    data = data.replace(old, new)
open(sys.argv[2], "wb").write(data)
EOF
  fi
  echo "wayland-backend.so=$copy"
}

if [ "$WINDOW" = "full" ]; then
  DISPLAY_SOCKET=wayland-0
else
  DISPLAY_SOCKET=waydroid-0
  W="${WINDOW%x*}"; H="${WINDOW#*x}"

  # Android's hwcomposer can't reconnect to a new compositor: if the window
  # is gone but the session survived, the new window would stay black.
  if ! systemctl --user is-active -q waydroid-weston && waydroid status | grep -q "Session:.*RUNNING"; then
    echo "==> Window was closed; restarting the Android session"
    waydroid session stop 2>/dev/null || true
    systemctl --user stop waydroid-session waydroid-ui 2>/dev/null || true
  fi

  # Android's clipboard lives in this Weston; the bridge module shares it
  # with Windows. Optional: without it Android still runs.
  CLIPBOARD=()
  if build_clipboard_bridge; then
    CLIPBOARD=(--setenv=ANDROID_WSL_CLIPBOARD_HELPER="python3 $SHARE/windows-clipboard.py"
               --setenv=ANDROID_WSL_POWERSHELL="$(command -v powershell.exe || true)")
  fi

  echo "==> Opening phone window (${W}x${H})"
  # Closing the window with its X shuts Android down (session, UI, adb bridge),
  # so the next start is clean. --no-block avoids waiting on our own stop job.
  run_unit waydroid-weston --setenv=WAYLAND_DISPLAY=wayland-0 "${CLIPBOARD[@]}" \
    --setenv=WESTON_MODULE_MAP="$(patch_weston_title)" \
    --property=ExecStopPost="/bin/sh -c 'waydroid session stop; systemctl --user stop --no-block waydroid-ui waydroid-adb-bridge waydroid-emu-console waydroid-session'" \
    weston --backend=wayland --shell=kiosk --socket="$DISPLAY_SOCKET" \
           --width="$W" --height="$H" --idle-time=0 \
           ${CLIPBOARD:+--modules="$SHARE/clipboard-bridge.so"}
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

# Both listeners are IPv4 on purpose: WSL forwards an IPv4 listener to the
# Windows 127.0.0.1, where adb scans ports 5555/5554 for emulators, so the
# device shows up as emulator-<port-1>. An IPv6 listener is only forwarded
# to ::1, which adb never scans.
CONSOLE_PORT=$((ADB_PORT - 1))
systemctl --user stop waydroid-adb-bridge waydroid-emu-console 2>/dev/null || true
pkill -f "^socat TCP4?-LISTEN:(${ADB_PORT}|${CONSOLE_PORT})," 2>/dev/null || true  # strays from a manual run
run_unit waydroid-adb-bridge socat "TCP4-LISTEN:${ADB_PORT},fork,reuseaddr" "TCP:${IP}:5555"
CONSOLE_SCRIPT="$SHARE/emu-console.sh"
install -D -m 755 "$HERE/emu-console.sh" "$CONSOLE_SCRIPT"
run_unit waydroid-emu-console socat "TCP4-LISTEN:${CONSOLE_PORT},fork,reuseaddr" EXEC:"bash $CONSOLE_SCRIPT"
echo "==> adb bridge: 127.0.0.1:${ADB_PORT} -> ${IP}:5555 (emulator-${CONSOLE_PORT})"
