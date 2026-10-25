#!/usr/bin/env bash
# Saves, restores and wipes Android's user data (apps, settings, files).
# The system image is not touched. Android must be stopped first.
#
#   ./snapshot.sh list
#   ./snapshot.sh save NAME | restore NAME | delete NAME
#   ./snapshot.sh wipe
set -euo pipefail

DATA="$HOME/.local/share/waydroid/data"
DIR="$HOME/.local/share/android-wsl/snapshots"
ACTION="${1:-list}"
NAME="${2:-}"

if [ "$ACTION" != list ] && waydroid status 2>/dev/null | grep -q "Session:.*RUNNING"; then
  echo "Android is running; stop it first." >&2
  exit 1
fi

need_name() {
  [[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "Snapshot names may only contain letters, digits, '.', '_' and '-'." >&2; exit 1; }
  FILE="$DIR/$NAME.tar.zst"
}

case "$ACTION" in
  list)
    mkdir -p "$DIR"
    shopt -s nullglob
    files=("$DIR"/*.tar.zst)
    if [ ${#files[@]} -eq 0 ]; then echo "No snapshots yet."; exit 0; fi
    for f in "${files[@]}"; do
      printf '%-24s %8s  %s\n' "$(basename "$f" .tar.zst)" \
        "$(du -h "$f" | cut -f1)" "$(date -r "$f" '+%Y-%m-%d %H:%M')"
    done
    ;;
  save)
    need_name
    mkdir -p "$DIR"
    echo "==> Saving snapshot '$NAME'"
    # Android's files belong to many app UIDs and carry SELinux labels:
    # keep numeric owners, permissions and xattrs exactly as they are.
    sudo tar --zstd -cpf "$FILE.tmp" --warning=no-file-ignored --numeric-owner --xattrs --xattrs-include='*' -C "$DATA" .
    sudo chown "$(id -u):$(id -g)" "$FILE.tmp"
    mv "$FILE.tmp" "$FILE"
    echo "    $(du -h "$FILE" | cut -f1)  $FILE"
    ;;
  restore)
    need_name
    [ -f "$FILE" ] || { echo "No snapshot named '$NAME'. See: snapshot list" >&2; exit 1; }
    echo "==> Restoring snapshot '$NAME'"
    # Extract next to the live data first so a failure leaves it untouched.
    sudo rm -rf "$DATA.restore"
    sudo mkdir -p "$DATA.restore"
    sudo tar --zstd -xpf "$FILE" --numeric-owner --xattrs --xattrs-include='*' -C "$DATA.restore"
    sudo rm -rf "$DATA"
    sudo mv "$DATA.restore" "$DATA"
    ;;
  delete)
    need_name
    [ -f "$FILE" ] || { echo "No snapshot named '$NAME'." >&2; exit 1; }
    rm -f "$FILE"
    echo "Deleted snapshot '$NAME'."
    ;;
  wipe)
    echo "==> Wiping Android data"
    # Waydroid recreates an empty data directory on the next start, so the
    # next boot is a first boot (a bit slower while apps are optimized).
    sudo rm -rf "$DATA"
    ;;
  *)
    echo "Usage: $0 list | save NAME | restore NAME | delete NAME | wipe" >&2
    exit 1
    ;;
esac
