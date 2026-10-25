#!/usr/bin/env bash
# Minimal Android emulator console, served by socat on the console port
# (adb port - 1). It is enough for tools that call `adb emu ...`:
#   avd name   -> device name shown by Expo, Android Studio, Flutter
#   kill       -> shuts Android down like closing the window
# Everything else answers "KO", as a real console does for unknown commands.
#
# adb skips the first two "OK" blocks of the reply (auth banner, then help
# banner), so the banners must match the real emulator's sequence.
set -uo pipefail

NAME="${EMU_AVD_NAME:-Waydroid}"
greeted=0

greet() {
  [ "$greeted" = 1 ] && return
  printf "Android Console: type 'help' for a list of commands\r\nOK\r\n"
  greeted=1
}

printf "Android Console: Authentication required\r\n"
printf "Android Console: type 'auth <auth_token>' to authenticate\r\n"
printf "Android Console: you can find your <auth_token> in\r\n"
printf "'~/.emulator_console_auth_token'\r\nOK\r\n"

while IFS= read -r line; do
  line="${line%$'\r'}"
  [ -n "${EMU_CONSOLE_LOG:-}" ] && printf '%s\n' "$line" >> "$EMU_CONSOLE_LOG"
  case "$line" in
    auth\ *)     greet; continue ;;   # any token is accepted
    quit|exit)   exit 0 ;;
  esac
  greet
  case "$line" in
    "avd name")   printf '%s\r\nOK\r\n' "$NAME" ;;
    "avd status") printf 'virtual device is running\r\nOK\r\n' ;;
    ping|"")      printf 'OK\r\n' ;;
    help)         printf 'avd name, avd status, kill, quit\r\nOK\r\n' ;;
    kill)
      printf 'OK: killing emulator, bye bye\r\n'
      systemctl --user stop --no-block waydroid-weston waydroid-ui
      exit 0 ;;
    *)            printf "KO: unknown command, try 'help'\r\n" ;;
  esac
done
