import AVFoundation
import Foundation
import Observation
import LiveKit
import os

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

@Observable
@MainActor
final class RoomController {
    /// Recreated on every connect: reusing one that errored causes signalling
    /// timeouts on the next join.
    private(set) var room: Room
    let frameStore = FrameStore()
    let audioMeters = AudioMeters()
    let presenterOverlay = PresenterOverlay()

    private(set) var state: ConnectionState = .disconnected
    /// The step currently being executed while joining, for the progress card.
    private(set) var joinPhase: JoinPhase = .idle
    private(set) var remoteParticipants: [RemoteParticipant] = []
    private(set) var renderers: [String: TrackRenderer] = [:]
    /// Tracks that have had statistics reporting switched on.
    private var meteredTrackIDs: Set<String> = []
    /// Logged once, because which source the meters use is the difference
    /// between accurate levels and the server's approximation.
    private var loggedMeterSource = false
    private(set) var cameraPublisher: CameraPublisher?
    private(set) var isCameraOn = false
    let markStore = MarkStore()
    private(set) var markTransport: MarkTransport?
    private(set) var localIdentity: String?
    private(set) var screenPublisher: ScreenPublisher?

    /// Key of the screen-share tile currently on the call, local or remote.
    private(set) var activeScreenShareID: String?
    private(set) var isSharingScreen = false
    private(set) var cameraFailure: String?
    private(set) var microphoneFailure: String?
    /// Set once echo cancellation has been given up to get a working
    /// microphone, so the UI can say so rather than leaving people wondering
    /// why they hear themselves.
    private(set) var voiceProcessingBypassed = false
    /// Remembered even when no publisher exists yet, so a camera chosen
    /// before switching the camera on is not silently discarded.
    private(set) var selectedCameraID: String?

    private let settings: SettingsStore
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "RoomController")

    init(settings: SettingsStore) {
        self.settings = settings
        self.room = Self.makeRoom()
        self.room.add(delegate: self)
    }

    /// A LiveKit identity is exclusive: a second client claiming the same one
    /// evicts the first, and a stale participant left by a crash blocks a
    /// rejoin — both show up as connection timeouts.
    nonisolated static func sessionIdentity(for personId: String, exact: Bool = false) -> String {
        exact ? personId : "\(personId)~\(UUID().uuidString.prefix(8))"
    }

    func connect(roomName: String, identity personId: String) async {
        guard settings.isMediaConfigured else {
            state = .failed("LiveKit settings are incomplete. Open Settings (⌘,).")
            joinPhase = .failed("LiveKit settings are incomplete. Open Settings (⌘,).")
            return
        }
        state = .connecting
        joinPhase = .preparing
        let identity = Self.sessionIdentity(for: personId, exact: settings.exactIdentity)
        localIdentity = identity

        // Start from a clean Room every time; see the property comment.
        await room.disconnect()
        renderers = [:]
        remoteParticipants = []
        cameraPublisher = nil
        screenPublisher = nil
        activeScreenShareID = nil
        isSharingScreen = false
        markStore.clearAll()
        markTransport = nil
        meteredTrackIDs = []
        audioMeters.clear()
        loggedMeterSource = false
        for id in frameStore.participantIDs { frameStore.remove(participantID: id) }
        room = Self.makeRoom()
        room.add(delegate: self)

        joinPhase = .signingToken
        let signer = TokenSigner(
            apiKey: settings.liveKitAPIKey,
            apiSecret: settings.liveKitAPISecret
        )
        let token = signer.sign(
            identity: identity,
            displayName: settings.displayName,
            room: roomName,
            ttl: 6 * 3600
        )

        // One retry: a transient signalling timeout on the first attempt is
        // common and almost always succeeds immediately afterwards.
        for attempt in 1 ... 2 {
            do {
                joinPhase = attempt == 1
                    ? .connecting(host: JoinPhase.host(of: settings.liveKitURL))
                    : .retrying
                try await room.connect(url: settings.liveKitURL, token: token)
                joinPhase = .enablingMicrophone
                // Deliberately not `try`: a microphone that will not start is
                // a degraded call, not a failed one.
                await enableMicrophone()
                joinPhase = .syncing
                state = .connected
                refreshParticipants()
                markTransport = MarkTransport(room: room, store: markStore, authorID: identity)
                joinPhase = .ready
                return
            } catch {
                if attempt == 1 {
                    logger.warning("Connect failed, retrying: \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(for: .seconds(1))
                    room = Self.makeRoom()
                    room.add(delegate: self)
                    continue
                }
                // Surface the real error: for a demo tool, blunt beats opaque.
                state = .failed("\(error)")
                joinPhase = .failed("\(error)")
            }
        }
    }

    func disconnect() async {
        await room.disconnect()
        remoteParticipants = []
        renderers = [:]
        state = .disconnected
        joinPhase = .idle
    }

    func setMicrophone(_ enabled: Bool) async {
        if enabled {
            await enableMicrophone()
        } else {
            microphoneFailure = nil
            try? await room.localParticipant.setMicrophone(enabled: false)
        }
    }

    /// Starts the microphone, giving up echo cancellation rather than the
    /// microphone if that is what it takes.
    func enableMicrophone() async {
        microphoneFailure = nil

        // Asked for explicitly rather than left to the audio engine: an
        // unanswered or denied prompt surfaced as a ten-second publish timeout
        // with nothing pointing at permissions.
        guard await MicrophonePermission.request() else {
            microphoneFailure = "Microphone access is denied. Enable UnbluMeet under "
                + "System Settings > Privacy & Security > Microphone."
            logger.error("Microphone access denied")
            return
        }

        do {
            try await room.localParticipant.setMicrophone(enabled: true)
            return
        } catch {
            guard Self.isAudioDeviceFailure(error) else {
                // Not a local audio problem, so retrying without voice
                // processing would change nothing.
                microphoneFailure = Self.explainMicrophone(error)
                logger.error("Microphone failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            logger.warning("Microphone failed, retrying without voice processing: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try AudioManager.shared.setPlatformVoiceProcessingAllowed(false)
            try await room.localParticipant.setMicrophone(enabled: true)
            voiceProcessingBypassed = true
        } catch {
            microphoneFailure = Self.explainMicrophone(error)
        }
    }

    /// Whether this is macOS failing to build its audio device, as opposed to
    /// the server refusing.
    nonisolated static func isAudioDeviceFailure(_ error: Error) -> Bool {
        let text = "\(error)".lowercased()
        return text.contains("timed out") || text.contains("timeout")
    }

    /// The server's own words when it has them.
    ///
    /// Every failure used to be reported as a CoreAudio problem, so a refusal
    /// from the server read as a broken microphone and sent people looking at
    /// their audio devices.
    nonisolated static func explainMicrophone(_ error: Error) -> String {
        let text = "\(error)"
        if text.lowercased().contains("permission") {
            return "The server refused to let this participant publish audio.\n\n"
                + "The access token grants publishing, so the room or the API key is "
                + "configured to withhold it.\n\n\(text)"
        }
        if isAudioDeviceFailure(error) {
            return "The microphone could not be started.\n\n"
                + "macOS could not build the audio device it needs. This usually clears "
                + "on a retry; if it keeps happening, a virtual audio driver or an iPhone "
                + "microphone connected over Continuity is often the cause — switching "
                + "input device in the microphone menu avoids it.\n\n\(text)"
        }
        return "The microphone could not be started.\n\n\(text)"
    }

    func clearMicrophoneFailure() {
        microphoneFailure = nil
    }

    /// Camera goes through our own capture path so background replacement can
    /// run before encoding; the SDK exposes no processor hook.
    func setCamera(_ enabled: Bool) async {
        isCameraOn = enabled
        if enabled {
            let publisher = cameraPublisher ?? CameraPublisher(
                room: room, frameStore: frameStore, localIdentity: localIdentity ?? "me",
                cameraDeviceID: selectedCameraID, presenterOverlay: presenterOverlay)
            cameraPublisher = publisher
            await publisher.start()
            cameraFailure = publisher.failure
        } else {
            cameraFailure = nil
            await cameraPublisher?.stop()
        }
    }

    func clearCameraFailure() {
        cameraFailure = nil
    }

    func selectCamera(_ deviceID: String) {
        selectedCameraID = deviceID
        cameraPublisher?.selectCamera(deviceID)
    }

    func setBackgroundMode(_ mode: BackgroundMode) {
        cameraPublisher?.backgroundMode = mode
    }

    func setPresenterOverlay(_ enabled: Bool) {
        presenterOverlay.isEnabled = enabled
        // The cut-out comes from camera frames, so the camera has to be
        // running while sharing even though nothing shows it on its own.
        guard isSharingScreen, isCameraOn else { return }
        Task {
            if enabled {
                await setCamera(true)
            } else {
                await cameraPublisher?.stop()
            }
        }
    }

    /// True while the presenter is being drawn onto their own share.
    var isPresenterOverlayActive: Bool {
        presenterOverlay.isEnabled && isSharingScreen
    }

    /// Who is sharing, derived from what participants have *published* rather
    /// than what we happen to be subscribed to.
    func refreshScreenShare() {
        if isSharingScreen, let mine = localIdentity {
            activeScreenShareID = Self.screenKey(for: mine)
            return
        }
        for participant in room.remoteParticipants.values {
            let hasScreenShare = participant.videoTracks.contains { publication in
                publication.source == .screenShareVideo
            }
            if hasScreenShare {
                activeScreenShareID = Self.screenKey(for: Self.identityKey(for: participant))
                return
            }
        }
        activeScreenShareID = nil
    }

    /// Every tile that should exist, derived from what participants have
    /// published.
    func videoTileKeys() -> [String] {
        var screens: [String] = []
        var cameras: [String] = []

        if isSharingScreen, let local = localIdentity {
            screens.append(Self.screenKey(for: local))
        }

        for participant in remoteParticipants {
            let identity = Self.identityKey(for: participant)
            for publication in participant.videoTracks {
                if publication.source == .screenShareVideo {
                    screens.append(Self.screenKey(for: identity))
                } else {
                    cameras.append(identity)
                }
            }
        }
        // Shares first so one can never be pushed onto a later page.
        return screens + cameras
    }

    /// Makes the renderer set match reality: every subscribed video track has
    /// a renderer attached, and nothing else does.
    func reconcileAudioMeters() {
        var seen: Set<String> = []
        for participant in room.remoteParticipants.values {
            for publication in participant.audioTracks {
                guard let remote = publication as? RemoteTrackPublication,
                      remote.isSubscribed,
                      let track = remote.track else { continue }
                let id = remote.sid.stringValue
                seen.insert(id)
                guard !meteredTrackIDs.contains(id) else { continue }
                meteredTrackIDs.insert(id)
                Task { await track.set(reportStatistics: true) }
                logger.info("Metering audio of \(Self.identityKey(for: participant), privacy: .public)")
            }
        }
        for id in meteredTrackIDs.subtracting(seen) {
            meteredTrackIDs.remove(id)
        }
    }

    func reconcileRenderers() {
        var wanted: [String: VideoTrack] = [:]

        for participant in room.remoteParticipants.values {
            let identity = Self.identityKey(for: participant)
            for publication in participant.videoTracks {
                guard let remote = publication as? RemoteTrackPublication,
                      remote.isSubscribed,
                      let track = remote.track as? VideoTrack else { continue }
                let key = remote.source == .screenShareVideo
                    ? Self.screenKey(for: identity) : identity
                wanted[key] = track
            }
        }

        for (key, track) in wanted where renderers[key] == nil {
            let renderer = TrackRenderer(participantID: key, store: frameStore)
            renderers[key] = renderer
            track.add(videoRenderer: renderer)
        }

        for key in renderers.keys where wanted[key] == nil {
            renderers.removeValue(forKey: key)
        }

        reconcileAudioMeters()
    }

    /// Participants in the call who publish no video at all.
    func audioOnlyParticipants() -> [RemoteParticipant] {
        remoteParticipants.filter { $0.videoTracks.isEmpty }
    }

    /// Every tile the grid should show: screens, cameras, then anyone with no
    /// video at all.
    func allTileKeys() -> [String] {
        var keys = videoTileKeys()
        for participant in audioOnlyParticipants() {
            keys.append(Self.identityKey(for: participant))
        }
        return keys
    }

    /// The remote participant currently speaking, if any.
    func refreshAudioLevels() {
        for participant in room.remoteParticipants.values {
            guard let reported = participant.audioTracks
                .compactMap({ $0.track?.statistics?.inboundRtpStream.first?.audioLevel })
                .max() else { continue }
            audioMeters.record(level: Float(reported), for: Self.identityKey(for: participant))
            if !loggedMeterSource {
                loggedMeterSource = true
                logger.info("Audio levels: inbound-RTP statistics")
            }
        }
    }

    func activeSpeaker() -> RemoteParticipant? {
        refreshAudioLevels()
        guard audioMeters.hasReadings else {
            return remoteParticipants.first { $0.isSpeaking }
        }
        let measured = audioMeters.all()
        let loudest = measured
            .filter { $0.value >= AudioLevelBars.audibleLevel }
            .max { $0.value < $1.value }
        guard let loudest else { return nil }
        return remoteParticipants.first { Self.identityKey(for: $0) == loudest.key }
    }

    /// Tile keys whose track we are actually receiving.
    func subscribedTileKeys() -> Set<String> {
        var keys: Set<String> = []
        if isSharingScreen, let local = localIdentity {
            keys.insert(Self.screenKey(for: local))
        }
        for participant in remoteParticipants {
            let identity = Self.identityKey(for: participant)
            for publication in participant.videoTracks {
                guard let remote = publication as? RemoteTrackPublication,
                      remote.isSubscribed else { continue }
                keys.insert(remote.source == .screenShareVideo
                            ? Self.screenKey(for: identity) : identity)
            }
        }
        return keys
    }

    /// Human-readable label for a tile key.
    func displayName(for tileKey: String) -> String {
        let isScreen = Self.isScreenKey(tileKey)
        let identity = isScreen
            ? String(tileKey.dropLast("#screen".count))
            : tileKey

        var name = identity
        if identity == localIdentity {
            name = settings.displayName
        } else if let participant = room.remoteParticipants.values.first(where: {
            Self.identityKey(for: $0) == identity
        }), let participantName = participant.name, !participantName.isEmpty {
            name = participantName
        }
        return isScreen ? "\(name) — screen" : name
    }

    func refreshParticipants() {
        // room.remoteParticipants is a Dictionary, so its order is unstable.
        remoteParticipants = room.remoteParticipants.values
            .sorted { Self.identityKey(for: $0) < Self.identityKey(for: $1) }
        // Covers anyone whose audio was already subscribed before we started
        // watching for it — track events only report changes.
        reconcileAudioMeters()
    }

    /// adaptiveStream and dynacast both default to false in the SDK.
    private static func makeRoom() -> Room {
        Room(roomOptions: RoomOptions(adaptiveStream: true, dynacast: true))
    }

    /// Screen shares get their own tile key: a participant can publish both a
    /// camera and a screen, and FrameStore is keyed by identity, so without a
    /// suffix the two would overwrite each other.
    nonisolated static func screenKey(for identity: String) -> String {
        "\(identity)#screen"
    }

    nonisolated static func isScreenKey(_ key: String) -> Bool {
        key.hasSuffix("#screen")
    }

    /// Only one participant may share.
    nonisolated static func shouldYieldShare(mine: String, theirs: String) -> Bool {
        mine < theirs
    }

    func startScreenShare(target: ShareTarget) async throws {
        guard let identity = localIdentity else { return }
        // The camera normally stops while sharing, but the overlay is cut from
        // its frames, so it has to keep running for there to be anything to
        // composite.
        if !presenterOverlay.isEnabled {
            await cameraPublisher?.stop()
        }
        let publisher = screenPublisher
            ?? ScreenPublisher(room: room, frameStore: frameStore,
                               localScreenID: Self.screenKey(for: identity),
                               presenterOverlay: presenterOverlay)
        screenPublisher = publisher
        try await publisher.start(target: target)
        isSharingScreen = true
        activeScreenShareID = Self.screenKey(for: identity)
    }

    func stopScreenShare() async {
        await screenPublisher?.stop()
        isSharingScreen = false
        if let identity = localIdentity,
           activeScreenShareID == Self.screenKey(for: identity) {
            activeScreenShareID = nil
        }
    }

    /// Identities currently speaking, and identities with the mic off.
    struct AudioState: Equatable {
        var speaking: Set<String> = []
        var muted: Set<String> = []
        /// 0…1 per participant, for the level meter on a tile.
        var levels: [String: Float] = [:]
    }

    /// Who is talking, how loudly, and who has actually muted themselves.
    func audioState() -> AudioState {
        refreshAudioLevels()
        var state = AudioState()
        for participant in room.remoteParticipants.values {
            let id = Self.identityKey(for: participant)

            // Statistics are the good source; the server's numbers only stand
            // in until the first one arrives.
            let level = audioMeters.hasReadings ? audioMeters.level(for: id) : participant.audioLevel
            state.levels[id] = level
            let audible = level >= AudioLevelBars.audibleLevel
            if audioMeters.hasReadings ? audible : (audible && participant.isSpeaking) {
                state.speaking.insert(id)
            }
            // getTrackPublication(source:) is internal to the SDK, so the
            // microphone publication is found by scanning what is published.
            if let microphone = participant.audioTracks.first(where: { $0.source == .microphone }),
               microphone.isMuted {
                state.muted.insert(id)
            }
        }
        return state
    }

    /// Single source of truth for participant identity.
    nonisolated static func identityKey(for participant: Participant) -> String {
        participant.identity?.stringValue ?? participant.sid?.stringValue ?? "unknown"
    }
}

extension RoomController: RoomDelegate {
    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant,
                          didSubscribeTrack publication: RemoteTrackPublication) {
        let identity = Self.identityKey(for: participant)
        let isScreen = publication.source == .screenShareVideo
        let id = isScreen ? Self.screenKey(for: identity) : identity
        Task { @MainActor in
            // Before the video guard below: this fires for audio tracks too,
            // and audio is where the level meters come from.
            self.reconcileAudioMeters()

            guard let videoTrack = publication.track as? VideoTrack else { return }
            let renderer = TrackRenderer(participantID: id, store: self.frameStore)
            self.renderers[id] = renderer
            videoTrack.add(videoRenderer: renderer)

            if isScreen {
                // Only one share at a time; deterministic tiebreak, no protocol.
                if self.isSharingScreen,
                   let mine = self.localIdentity,
                   Self.shouldYieldShare(mine: mine, theirs: identity) {
                    await self.stopScreenShare()
                }
            }
            self.refreshScreenShare()
            self.refreshParticipants()
        }
    }

    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant,
                          didUnsubscribeTrack publication: RemoteTrackPublication) {
        let identity = Self.identityKey(for: participant)
        let id = publication.source == .screenShareVideo
            ? Self.screenKey(for: identity) : identity
        Task { @MainActor in
            // Deliberately not clearing activeScreenShareID here:
            // unsubscribing means we stopped watching, not that the sharer
            // stopped sharing.
            self.refreshScreenShare()
            self.reconcileAudioMeters()
            if let renderer = self.renderers.removeValue(forKey: id),
               let videoTrack = publication.track as? VideoTrack {
                videoTrack.remove(videoRenderer: renderer)
            }
            // The last frame is kept deliberately: unsubscribing means we
            // stopped watching, so the tile freezes rather than going black.
            self.refreshParticipants()
        }
    }

    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant?,
                          didReceiveData data: Data,
                          forTopic topic: String,
                          encryptionType: EncryptionType) {
        switch topic {
        case MarkTransport.topic:
            guard let mark = try? Mark.decode(data) else { return }
            markStore.add(mark)
        case MarkTransport.calloutTopic:
            guard let callout = try? Callout.decode(data) else { return }
            markStore.add(callout)
        default:
            return
        }
    }

    /// A call can end without anyone asking it to — the network drops, the
    /// server restarts, another client claims this identity.
    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            // A disconnect we asked for has already set this; only an
            // unexpected one still looks connected here.
            guard self.state == .connected else { return }
            if let error {
                self.state = .failed("\(error)")
                self.joinPhase = .failed("\(error)")
            } else {
                self.state = .disconnected
                self.joinPhase = .idle
            }
            self.remoteParticipants = []
            self.renderers = [:]
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.refreshScreenShare()
            self.refreshParticipants()
        }
    }

    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant,
                          didPublishTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            self.refreshScreenShare()
            // The tile list is derived from publications, so it must be
            // recomputed here or a new track never gets a tile.
            self.refreshParticipants()
        }
    }

    nonisolated func room(_ room: Room,
                          participant: RemoteParticipant,
                          didUnpublishTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            self.refreshScreenShare()
            self.refreshParticipants()
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        let id = Self.identityKey(for: participant)
        Task { @MainActor in
            self.renderers.removeValue(forKey: id)
            self.renderers.removeValue(forKey: Self.screenKey(for: id))
            self.frameStore.remove(participantID: id)
            self.frameStore.remove(participantID: Self.screenKey(for: id))
            self.refreshScreenShare()
            self.refreshParticipants()
        }
    }
}
