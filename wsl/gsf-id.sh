#!/usr/bin/env bash
# Prints the Google Services Framework Android ID, which Google's device
# registration page (google.com/android/uncertified) asks for. GAPPS only.
# Exit codes: 2 = no Google Services Framework, 3 = no ID generated yet.
set -euo pipefail

DB="$HOME/.local/share/waydroid/data/data/com.google.android.gsf/databases/gservices.db"
if ! sudo test -f "$DB"; then
  echo "Google Services Framework not found. Is this a GAPPS image? (android.ps1 setup -Gapps)" >&2
  exit 2
fi

# Read a copy, with its write-ahead log: Android keeps the live database open.
TMP="$(mktemp -d)"
trap 'sudo rm -rf "$TMP"' EXIT
sudo cp "$DB" "$TMP/"
if sudo test -f "$DB-wal"; then sudo cp "$DB-wal" "$TMP/"; fi
sudo python3 - "$TMP/gservices.db" <<'EOF'
import sqlite3, sys
row = sqlite3.connect(sys.argv[1]).execute("select value from main where name = 'android_id'").fetchone()
if not row:
    sys.exit(3)
print(row[0])
EOF
