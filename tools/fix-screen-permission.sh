#!/bin/bash
# Clears a stale Screen Recording grant and the quarantine flag that causes
# macOS to run the app from a throwaway location.
#
# Usage: tools/fix-screen-permission.sh [/path/to/UnbluMeet.app]
set -euo pipefail

APP="${1:-/Applications/UnbluMeet.app}"
BUNDLE_ID="com.unblu.UnbluMeet"

osascript -e 'quit app "UnbluMeet"' 2>/dev/null || true

echo "Resetting Screen Recording for $BUNDLE_ID…"
tccutil reset ScreenCapture "$BUNDLE_ID"

if [ -d "$APP" ]; then
    echo "Clearing quarantine on $APP…"
    xattr -dr com.apple.quarantine "$APP" || true
    case "$APP" in
        /Applications/*) ;;
        *) echo "NOTE: $APP is not in /Applications. Move it there — a copy run from"
           echo "      Downloads is relaunched from a new path each time, and no"
           echo "      Screen Recording grant can survive that." ;;
    esac
else
    echo "NOTE: $APP not found; skipped the quarantine step."
fi

echo "Done. Launch UnbluMeet and allow the prompt when it appears."
