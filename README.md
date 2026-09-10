# UnbluMeet

A native macOS conferencing app built on LiveKit for media and the Unblu Web
API v4 for conversations and chat. Internal demo tool.

Video is composited with Metal rather than one view per participant, which is
what makes 100 participants practical: unwatched tiles are unsubscribed and
their publishers stop uploading.

## What it does

- Grid, speaker and pinned layouts; drag tiles to rearrange them
- Screen and window sharing, including a region of a screen
- Annotation on a share: freehand marks and magnified callouts
- Live captions and a running call summary, both on device
- Background blur, and drawing the presenter over their own share
- Chat with file attachments, backed by the Unblu conversation

## Building

```
xcodegen generate
open UnbluMeet.xcodeproj
```

Requires XcodeGen (`brew install xcodegen`) and macOS 26. Sources live in
file-system-synchronized folders, so adding a file needs no regeneration —
only a change to `project.yml` does.

## Configuration

No credentials ship in the source. On first launch, open Settings (⌘,) and
fill in:

- **LiveKit** — server URL, API key and secret. Tokens are signed locally, so
  no token service is needed.
- **Unblu** — Web API base URL, username and password. The address may stop at
  the host; `/app/rest/v4` is appended if missing.

Values are kept in UserDefaults, secrets in the keychain.

## Simulating participants

Fills a room with people who have faces and voices, so layouts, captions,
speaking indicators and the summary can be exercised alone:

```
LIVEKIT_URL=wss://… LIVEKIT_API_KEY=… LIVEKIT_API_SECRET=… \
  tools/simulate-participants.sh --room <conversation-id> --participants 8 --talkers 3
```

The room name is the Unblu conversation id. `--stop` ends a run.

## Tests

```
xcodebuild test -project UnbluMeet.xcodeproj -scheme UnbluMeet \
  -destination 'platform=macOS,arch=arm64'
```
