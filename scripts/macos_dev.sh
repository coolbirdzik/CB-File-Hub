#!/usr/bin/env bash

# Run the macOS debug build with its own privacy permissions, then attach for
# hot reload.
#
# `flutter run -d macos` starts the app as a child of the terminal, so macOS
# checks privacy permissions (Full Disk Access, Files & Folders...) against the
# "responsible" parent (VS Code, Terminal) instead of CB File Hub. Granting
# them to CB File Hub then has no effect on the dev build. Launching through
# LaunchServices (`open`) makes the app responsible for itself; `flutter
# attach` then connects to its VM service for hot reload / restart.
#
# Usage (from the repo root, extra args go to `flutter build` and `flutter
# attach`, e.g. --dart-define-from-file=../.env):
#   scripts/macos_dev.sh [flutter args...]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/../cb_file_manager" && pwd)"
APP="$PROJECT_DIR/build/macos/Build/Products/Debug/CB File Hub.app"
BINARY="$APP/Contents/MacOS/CB File Hub"
LOG="$PROJECT_DIR/build/macos/dev_app.log"

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "macos-dev only runs on macOS" >&2
    exit 1
fi

cd "$PROJECT_DIR"

# A previous dev instance would keep the old code; the installed app in
# /Applications is left alone.
pkill -f "$BINARY" 2>/dev/null && sleep 1 || true

flutter build macos --debug "$@"

: > "$LOG"
# -n: start a new instance even when the installed app (same bundle id) runs.
open -n --stdout "$LOG" --stderr "$LOG" "$APP"

echo "Waiting for the Dart VM service (log: $LOG)..."
URL=""
for _ in $(seq 1 120); do
    URL=$(grep -oE 'http://127\.0\.0\.1:[0-9]+/[^ ]*' "$LOG" | tail -n 1 || true)
    [ -n "$URL" ] && break
    if [ "$(grep -c . "$LOG")" -gt 0 ] && ! pgrep -f "$BINARY" >/dev/null; then
        echo "The app exited before its VM service started:" >&2
        tail -n 30 "$LOG" >&2
        exit 1
    fi
    sleep 0.5
done
if [ -z "$URL" ]; then
    echo "No VM service URL after 60s:" >&2
    tail -n 30 "$LOG" >&2
    exit 1
fi

# App logs (print/debugPrint) keep going to $LOG: `tail -f` it in another tab.
exec flutter attach -d macos --debug-url "$URL" "$@"
