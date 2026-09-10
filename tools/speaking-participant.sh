#!/usr/bin/env bash
# Joins a room as a participant that speaks synthesized text on a loop, so
# captions and speaking indicators can be tested without a second person.
#
#   ./tools/speaking-participant.sh <conversation-id> [name] [minutes]
set -euo pipefail

ROOM="${1:?usage: speaking-participant.sh <conversation-id> [name] [minutes]}"
NAME="${2:-Narrator}"
MINUTES="${3:-10}"

export LIVEKIT_URL="${LIVEKIT_URL:?set LIVEKIT_URL}"
export LIVEKIT_API_KEY="${LIVEKIT_API_KEY:?set LIVEKIT_API_KEY}"
export LIVEKIT_API_SECRET="${LIVEKIT_API_SECRET:?set LIVEKIT_API_SECRET}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say -v Samantha -o "$WORK/speech.aiff" \
  "Hello, this is $NAME speaking. Live captions should be transcribing these words right now. \
   The quick brown fox jumps over the lazy dog. \
   Testing one, two, three. Screen sharing, annotations, and chat all appear to be working."

# Opus in Ogg is what the LiveKit CLI publishes.
ffmpeg -y -loglevel error -i "$WORK/speech.aiff" -c:a libopus -b:a 32k -ar 48000 -ac 1 "$WORK/speech.ogg"

# One pass is around fifteen seconds; repeat to cover the requested duration.
LOOPS=$(( MINUTES * 4 ))
ffmpeg -y -loglevel error -stream_loop "$LOOPS" -i "$WORK/speech.ogg" -c copy "$WORK/loop.ogg"

# LiveKit identities are exclusive, and a previous run can still be held by
# the server — reusing the name fails with "could not connect after timeout".
IDENTITY="$NAME-$RANDOM"

echo "Joining $ROOM as $IDENTITY for about $MINUTES minutes..."
lk room join --room "$ROOM" --identity "$IDENTITY" --publish "$WORK/loop.ogg"
