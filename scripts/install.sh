#!/bin/bash
# Builds Clipboard Shelf, installs it into /Applications (or --dest DIR), turns on launch at login
# and starts it.
#   scripts/install.sh               build from source and install
#   scripts/install.sh --dest DIR    install into DIR instead
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=/Applications
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="$2"; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

./build.sh
APP="$DEST/ClipboardShelf.app"
pkill -x ClipboardShelf 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -x ClipboardShelf >/dev/null || break; sleep 0.25; done
rm -rf "$APP"
ditto build/ClipboardShelf.app "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "Installed $APP"
echo "Launch at login: $("$APP/Contents/MacOS/ClipboardShelf" --register-login-item)"
open "$APP"
