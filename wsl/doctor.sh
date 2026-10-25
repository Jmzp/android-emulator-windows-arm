#!/usr/bin/env bash
# Linux-side checks for `android.ps1 doctor`. Prints one line per check:
#   PASS|<what>        WARN|<what>|<fix>        FAIL|<what>|<fix>        INFO|<what>
set -uo pipefail

ADB_PORT="${ADB_PORT:-5555}"
CONSOLE_PORT=$((ADB_PORT - 1))
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

pass() { echo "PASS|$1"; }
warn() { echo "WARN|$1|$2"; }
fail() { echo "FAIL|$1|$2"; }
info() { echo "INFO|$1"; }

# Kernel
release="$(uname -r)"
case "$release" in
  *-waydroid*) pass "Custom kernel loaded ($release)" ;;
  *) fail "Stock WSL kernel loaded ($release)" "Run .\\windows\\install-kernel.ps1" ;;
esac
if grep -q binder /proc/filesystems; then pass "binder available"; else fail "binder missing in kernel" "Run .\\windows\\install-kernel.ps1"; fi

# systemd and lingering
if [ "$(cat /proc/1/comm)" = "systemd" ]; then pass "systemd is PID 1"
else fail "systemd is not running" "Run .\\windows\\setup-wsl.ps1, then wsl --shutdown"; fi
if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" = "yes" ]; then pass "User lingering enabled"
else fail "User lingering disabled" "Run .\\windows\\android.ps1 setup"; fi

# Packages
for bin in waydroid weston socat; do
  if command -v "$bin" >/dev/null; then pass "$bin installed"
  else fail "$bin not installed" "Run .\\windows\\android.ps1 setup"; fi
done
if [ -f /var/lib/waydroid/waydroid.cfg ]; then pass "Android images initialized"
else fail "Android images not downloaded" "Run .\\windows\\android.ps1 setup"; fi
if grep -qE '^persist\.waydroid\.(width|height)' /var/lib/waydroid/waydroid.cfg 2>/dev/null; then
  warn "Fixed width/height set in waydroid.cfg (causes a black screen)" "Run .\\windows\\android.ps1 setup to remove them"
fi

if systemctl is-active -q waydroid-container; then pass "waydroid-container service active"
else fail "waydroid-container service inactive" "sudo systemctl enable --now waydroid-container"; fi

# Runtime: only meaningful while Android is running
if ! waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; then
  info "Android is not running. Start it with .\\windows\\android.ps1 start to check the runtime too"
  exit 0
fi
pass "Android session running"

# waydroid-ui is not listed: `waydroid show-full-ui` exits once the UI is up.
for unit in waydroid-weston waydroid-session waydroid-adb-bridge waydroid-emu-console; do
  if systemctl --user is-active -q "$unit"; then pass "$unit active"
  elif [ "$unit" = waydroid-weston ]; then info "No phone window (started with -Full?)"
  else warn "$unit inactive" "Restart with .\\windows\\android.ps1 stop, then start"; fi
done

if [ "$(sudo -n waydroid shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then pass "Android finished booting"
else fail "Android has not finished booting" "sudo waydroid logcat -b crash"; fi

if ss -ltn "sport = :$ADB_PORT" | grep -q "0.0.0.0:$ADB_PORT"; then pass "adb bridge listening on IPv4 :$ADB_PORT"
else fail "adb bridge not listening on IPv4 :$ADB_PORT" "Run .\\windows\\android.ps1 stop, then start"; fi
if ss -ltn "sport = :$CONSOLE_PORT" | grep -q "0.0.0.0:$CONSOLE_PORT"; then pass "Emulator console listening on :$CONSOLE_PORT"
else warn "Emulator console not listening on :$CONSOLE_PORT" "Run .\\windows\\android.ps1 stop, then start"; fi

# "--" keeps waydroid's own argument parser from eating ping's options.
if sudo -n waydroid shell -- ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then pass "Android has internet access"
else warn "Android has no internet access" "sudo waydroid container restart; check sudo iptables -t nat -L"; fi
