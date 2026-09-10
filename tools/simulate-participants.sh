#!/usr/bin/env bash
# Fills a room with simulated participants that have faces and voices, so
# layouts, captions, speaking indicators and the call summary can be exercised
# without a room full of people.
#
# Each participant publishes a looping animated avatar. Only some of them talk,
# and those speak in bursts with long gaps, the way people actually do on a
# call — a room where everyone talks continuously tests nothing.
#
#   tools/simulate-participants.sh --room <conversation-id> --participants 8 --talkers 3
#   tools/simulate-participants.sh --stop
#
# Ctrl-C stops everything it started.
set -euo pipefail

ROOM=""
PARTICIPANTS=6
TALKERS=3
MINUTES=20
FPS=15
SIZE="640x360"
VIDEO_DIR=""
NO_VIDEO=0
NAMES=""
VOICE_ARG=""
MIN_GAP=5
MAX_GAP=18
STOP=0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${TMPDIR:-/tmp}/unblumeet-sim"
PID_FILE="$STATE_DIR/pids"

usage() {
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'USAGE'

Options:
  --room ID            Conversation id — the LiveKit room name (required)
  --participants N     How many to simulate            (default 6)
  --talkers N          How many of them speak          (default 3)
  --minutes N          How long the audio lasts        (default 20)
  --fps N              Video frame rate                (default 15)
  --size WxH           Video size                      (default 640x360)
  --names "A,B,C"      Use these names instead of the built-in list
  --voices "X,Y"       Use these macOS voices instead of the built-in list
  --min-gap N          Shortest silence between utterances   (default 5)
  --max-gap N          Longest silence between utterances    (default 18)
  --video-dir DIR      Publish real clips from DIR instead of drawn avatars
  --no-video           Audio only
  --stop               Stop a previous run and exit
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --room) ROOM="$2"; shift 2 ;;
        --participants) PARTICIPANTS="$2"; shift 2 ;;
        --talkers) TALKERS="$2"; shift 2 ;;
        --minutes) MINUTES="$2"; shift 2 ;;
        --fps) FPS="$2"; shift 2 ;;
        --size) SIZE="$2"; shift 2 ;;
        --names) NAMES="$2"; shift 2 ;;
        --voices) VOICE_ARG="$2"; shift 2 ;;
        --min-gap) MIN_GAP="$2"; shift 2 ;;
        --max-gap) MAX_GAP="$2"; shift 2 ;;
        --video-dir) VIDEO_DIR="$2"; shift 2 ;;
        --no-video) NO_VIDEO=1; shift ;;
        --stop) STOP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

stop_previous() {
    [ -f "$PID_FILE" ] || { echo "Nothing running."; return; }
    while read -r pid; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null && echo "  stopped $pid" || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
    echo "Stopped."
}

if [ "$STOP" -eq 1 ]; then stop_previous; exit 0; fi
[ -n "$ROOM" ] || { echo "--room is required" >&2; usage; exit 1; }

export LIVEKIT_URL="${LIVEKIT_URL:?set LIVEKIT_URL}"
export LIVEKIT_API_KEY="${LIVEKIT_API_KEY:?set LIVEKIT_API_KEY}"
export LIVEKIT_API_SECRET="${LIVEKIT_API_SECRET:?set LIVEKIT_API_SECRET}"

command -v lk >/dev/null      || { echo "lk not found (brew install livekit-cli)" >&2; exit 1; }
command -v ffmpeg >/dev/null  || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }

DEFAULT_NAMES="Anna Weber,Marek Novak,Sofia Rossi,Tomas Berg,Lena Fischer,Pavel Horak,Nina Costa,Jonas Lund,Iris Meyer,Adam Kovac,Petra Svoboda,Karim Haddad"
IFS=',' read -r -a NAME_LIST <<< "${NAMES:-$DEFAULT_NAMES}"

# An explicit list of speaking voices, intersected with what is installed.
# Taking the first few en_ voices alphabetically picked Bahh, Bells, Boing,
# Bubbles, Cellos and Wobble — macOS novelty voices, which are sound effects
# rather than speech and are no use to the transcriber either.
NATURAL_VOICES=(Samantha Daniel Karen Moira Tessa Rishi Tara Kathy Serena Nicky Alex Ava Allison Susan Evan)
INSTALLED="$(say -v '?' 2>/dev/null | awk '{print $1}')"
VOICES=()
for v in "${NATURAL_VOICES[@]}"; do
    grep -qx "$v" <<< "$INSTALLED" && VOICES+=("$v")
done
if [ -n "$VOICE_ARG" ]; then
    IFS=',' read -r -a VOICES <<< "$VOICE_ARG"
fi
[ ${#VOICES[@]} -gt 0 ] || VOICES=("Samantha")

# Things worth summarising: decisions and owners, not filler, so the AI panel
# has something real to extract.
LINES=(
"I looked at the release blocker this morning and the fix is smaller than we thought."
"My proposal is that we move this to the next sprint, because the dependency is not ready yet."
"Agreed, let us ship without it and document the limitation in the release notes."
"I can take the documentation and have a draft ready by Wednesday evening."
"One caveat, the customer asked for an update, so somebody should reply to them today."
"The android build is still failing on the device wide capture path, I will look at it."
"Can we decide on the deadline now, because the release notes go out on Friday morning."
"I disagree, I think the risk of shipping that change this late is too high."
"Fine, let us keep it behind a flag and turn it on for internal accounts first."
"That closes this topic, who is taking the next one."
"The performance numbers look acceptable, about two hundred milliseconds on average."
"We should tell support before this goes out, otherwise they will be surprised."
)

WORK="$STATE_DIR/work"
mkdir -p "$WORK"
rm -f "$PID_FILE"; touch "$PID_FILE"

WIDTH="${SIZE%x*}"; HEIGHT="${SIZE#*x}"

cleanup() {
    echo
    echo "Stopping simulated participants..."
    while read -r pid; do [ -n "$pid" ] && kill "$pid" 2>/dev/null || true; done < "$PID_FILE"
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup INT TERM

# --- media -----------------------------------------------------------------

# Two seconds per clip, rendered twice per participant: quiet and talking. The
# session's video is those two laid end to end following the same schedule the
# audio was built from, so a mouth moves only while that person is speaking.
#
# Two rather than one because motion has to complete whole cycles within a clip
# to concatenate seamlessly: at one second the background had to drift so
# little that a silent participant looked like a still photograph.
LOOP_SECONDS=2

# Compiled once. `swift file.swift` recompiles on every run, which at two
# clips per participant was most of the startup cost.
AVATAR_BIN="$WORK/avatar-video"
build_renderer() {
    [ -x "$AVATAR_BIN" ] && return
    # swiftc only accepts top-level code in a file called main.swift.
    cp "$HERE/avatar-video.swift" "$WORK/main.swift"
    swiftc -O -o "$AVATAR_BIN" "$WORK/main.swift" 2>/dev/null ||
        { echo "  (renderer would not compile; falling back to interpreting it)"; AVATAR_BIN=""; }
}

# The app labels every tile itself, so the clip carries no name.
render_clip() {  # index talking destination
    local index="$1" talking="$2" out="$3"
    local renderer=("$AVATAR_BIN")
    [ -z "$AVATAR_BIN" ] && renderer=(swift "$HERE/avatar-video.swift")
    "${renderer[@]}" \
        --width "$WIDTH" --height "$HEIGHT" --fps "$FPS" \
        --seconds "$LOOP_SECONDS" --seed "$index" --talking "$talking" 2>/dev/null |
    ffmpeg -y -loglevel error \
        -f rawvideo -pix_fmt rgba -s "${WIDTH}x${HEIGHT}" -r "$FPS" -i - \
        -c:v libx264 -preset veryfast -profile:v baseline -pix_fmt yuv420p \
        -g "$FPS" -bf 0 -f h264 "$out"
}

make_avatar() {  # index name -> path
    local index="$1" name="$2"
    local out="$WORK/avatar-$index.h264"
    [ -f "$out" ] && { echo "$out"; return; }

    local quiet="$WORK/quiet-$index.h264" talk="$WORK/talkclip-$index.h264"
    render_clip "$index" 0 "$quiet"
    render_clip "$index" 1 "$talk"

    : > "$out"
    local schedule="$WORK/schedule-$index.txt"
    if [ -f "$schedule" ]; then
        # Follow this participant's own speech schedule.
        while read -r kind clips; do
            local clip="$quiet"
            [ "$kind" = "talk" ] && clip="$talk"
            append_clip "$clip" "$clips" "$out"
        done < "$schedule"
    else
        # Nobody who says nothing needs a talking clip.
        append_clip "$quiet" $(( MINUTES * 60 / LOOP_SECONDS )) "$out"
    fi
    echo "$out"
}

# One cat for the whole segment: a twenty-minute clip is more than a thousand
# seconds, and spawning a process for each was minutes of pure overhead.
append_clip() {  # clip seconds destination
    local clip="$1" count="$2" out="$3"
    local args=()
    local n=0
    while [ "$n" -lt "$count" ]; do args+=("$clip"); n=$(( n + 1 )); done
    [ ${#args[@]} -gt 0 ] && cat "${args[@]}" >> "$out"
}

# Plain byte concatenation, not ffmpeg -stream_loop: that needs to seek its
# input and a raw Annex-B stream is not seekable, so it produced a truncated
# file and no video track at all. Each loop begins with SPS/PPS and a keyframe,
# which is exactly what makes concatenation valid here — verified by frame
# count, 300 becoming 2700 over nine copies.
repeat_h264() {  # source destination seconds-per-loop
    local source="$1" destination="$2" seconds="$3"
    local loops=$(( (MINUTES * 60) / seconds + 1 ))
    : > "$destination"
    for _ in $(seq 1 "$loops"); do cat "$source" >> "$destination"; done
}

use_clip() {  # index -> path, transcoding whatever the user supplied
    local index="$1"
    local clips=("$VIDEO_DIR"/*)
    local clip="${clips[$(( index % ${#clips[@]} ))]}"
    local out="$WORK/clip-$index.h264"
    [ -f "$out" ] && { echo "$out"; return; }
    local once="$WORK/clip-once-$index.h264"
    ffmpeg -y -loglevel error -i "$clip" -an \
        -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT},fps=${FPS}" \
        -c:v libx264 -preset veryfast -profile:v baseline -pix_fmt yuv420p \
        -g "$FPS" -bf 0 -f h264 "$once"
    # Repeat the supplied clip too: it is unlikely to be as long as the session.
    local seconds
    seconds=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$clip" 2>/dev/null | cut -d. -f1)
    repeat_h264 "$once" "$out" "${seconds:-10}"
    echo "$out"
}

# Cached by length: with gaps of five to eighteen seconds there are only a
# dozen or so distinct ones in a session, and each was being rendered afresh.
silence_file() {  # seconds -> path
    # Two statements, not one: `local` expands all its arguments before any of
    # them are assigned, so a second variable cannot refer to the first.
    local seconds="$1"
    local path="$WORK/silence-$seconds.wav"
    [ -f "$path" ] || ffmpeg -y -loglevel error -f lavfi -i "anullsrc=r=48000:cl=mono" \
        -t "$seconds" -c:a pcm_s16le "$path"
    echo "$path"
}

# Advances both clocks and reports how many whole seconds of video this
# segment gets, chosen so the running totals stay together rather than each
# segment rounding independently.
# Counted in clips, not seconds: a clip is the smallest unit the video can be
# built from, so rounding has to happen there. Rounding each segment up on its
# own put a talker's video twenty-three seconds ahead of their voice over six
# minutes.
schedule_segment() {  # exact emittedClips duration -> exact emittedClips clips
    awk -v exact="$1" -v emitted="$2" -v duration="$3" -v loop="$LOOP_SECONDS" 'BEGIN {
        exact += duration
        target = int(exact / loop + 0.5)
        clips = target - emitted
        if (clips < 1) { clips = 1; target = emitted + 1 }
        printf "%.3f %d %d\n", exact, target, clips
    }'
}

# Speech bursts separated by long silences: the gaps are the point, since a
# summary of everyone talking at once is not a test of anything.
make_speech() {  # index name -> path
    local index="$1" name="$2"
    local out="$WORK/speech-$index.ogg"
    [ -f "$out" ] && { echo "$out"; return; }

    local voice="${VOICES[$(( index % ${#VOICES[@]} ))]}"
    local dir="$WORK/speech-$index"; rm -rf "$dir"; mkdir -p "$dir"
    local list="$dir/list.txt"; : > "$list"
    # Written for make_avatar, so the mouth and the voice agree.
    local schedule="$WORK/schedule-$index.txt"; : > "$schedule"

    # Two clocks: the exact audio position, and how many whole seconds of video
    # have been written for it. Rounding each segment on its own drifted the
    # mouth away from the voice — a couple of seconds over two minutes, which
    # over a long session becomes obvious.
    local exact=0 emitted=0
    local elapsed=0 piece=0
    # Stagger the start so they do not all begin together.
    local gap=$(( 2 + (index * 5) % 9 ))
    while [ "$elapsed" -lt $(( MINUTES * 60 )) ]; do
        echo "file '$(silence_file "$gap")'" >> "$list"
        read -r exact emitted clips < <(schedule_segment "$exact" "$emitted" "$gap")
        echo "quiet $clips" >> "$schedule"
        elapsed=$(( elapsed + gap ))

        local line="${LINES[$(( (index * 5 + piece * 3) % ${#LINES[@]} ))]}"
        say -v "$voice" -o "$dir/say-$piece.aiff" "$line"
        ffmpeg -y -loglevel error -i "$dir/say-$piece.aiff" \
            -ar 48000 -ac 1 -c:a pcm_s16le "$dir/talk-$piece.wav"
        echo "file '$dir/talk-$piece.wav'" >> "$list"
        # Measured, not assumed: sentences vary by seconds, and a guess here
        # would drift the mouth away from the voice over a long session.
        local spoken
        spoken=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dir/talk-$piece.wav")
        read -r exact emitted clips < <(schedule_segment "$exact" "$emitted" "${spoken:-6}")
        echo "talk $clips" >> "$schedule"
        elapsed=$(( elapsed + clips * LOOP_SECONDS ))

        local spread=$(( MAX_GAP - MIN_GAP + 1 ))
        [ "$spread" -lt 1 ] && spread=1
        gap=$(( MIN_GAP + RANDOM % spread ))
        piece=$(( piece + 1 ))
    done

    ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" \
        -c:a libopus -b:a 32k -ar 48000 -ac 1 "$out"
    echo "$out"
}

# --- run -------------------------------------------------------------------

echo "Room:         $ROOM"
echo "Server:       $LIVEKIT_URL"
echo "Participants: $PARTICIPANTS ($TALKERS of them speaking)"
echo

# Media first, everyone at once. Building it inline with joining meant each
# participant waited for every earlier one to be rendered, so with eight of
# them the last arrived minutes after the first.
build_renderer

prepare() {  # index -> writes the publish arguments for this participant
    local index="$1" name="$2"
    local args="$WORK/args-$index.txt"
    : > "$args"

    local speech=""
    if [ "$index" -lt "$TALKERS" ]; then
        # Before the avatar: it reads the schedule this writes.
        speech="$(make_speech "$index" "$name")"
    fi

    if [ "$NO_VIDEO" -eq 0 ]; then
        if [ -n "$VIDEO_DIR" ]; then
            echo "$(use_clip "$index")" >> "$args"
        else
            echo "$(make_avatar "$index" "$name")" >> "$args"
        fi
    fi
    [ -n "$speech" ] && echo "$speech" >> "$args"
}

echo "Preparing media..."
STARTED_AT=$SECONDS
for i in $(seq 0 $(( PARTICIPANTS - 1 ))); do
    NAME="${NAME_LIST[$(( i % ${#NAME_LIST[@]} ))]}"
    prepare "$i" "$NAME" &
done
wait
echo "  ready in $(( SECONDS - STARTED_AT ))s"
echo

for i in $(seq 0 $(( PARTICIPANTS - 1 ))); do
    NAME="${NAME_LIST[$(( i % ${#NAME_LIST[@]} ))]}"
    # LiveKit identities are exclusive and a crashed run can still be held by
    # the server, so each gets a suffix.
    IDENTITY="$NAME $(( RANDOM % 900 + 100 ))"

    PUBLISH=()
    while read -r file; do PUBLISH+=(--publish "$file"); done < "$WORK/args-$i.txt"

    if [ "$i" -lt "$TALKERS" ]; then
        printf '  %-22s video: %s  speech: yes\n' "$NAME" \
            "$([ "$NO_VIDEO" -eq 1 ] && echo none || echo yes)"
    else
        printf '  %-22s video: %s  speech: no\n' "$NAME" \
            "$([ "$NO_VIDEO" -eq 1 ] && echo none || echo yes)"
    fi

    # Leaving when the media ends beats lingering on a last frame that looks
    # like a stalled video.
    lk room join --room "$ROOM" --identity "$IDENTITY" --fps "$FPS" \
        --exit-after-publish "${PUBLISH[@]}" >"$WORK/log-$i.txt" 2>&1 &
    echo $! >> "$PID_FILE"
    sleep 0.2
done

echo
echo "Running. Ctrl-C to stop, or: tools/simulate-participants.sh --stop"
wait
