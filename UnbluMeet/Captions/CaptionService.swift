import Foundation
import Speech
import AVFoundation
import LiveKit
import Observation
import os

/// Live captions for whoever is currently speaking.
@Observable
@MainActor
final class CaptionService {
    enum Mode: Equatable {
        case off
        case onDevice
        case server          // audio leaves the machine; surfaced, never silent
        case unavailable(String)
    }

    private(set) var mode: Mode = .off
    private(set) var speakerName: String = ""
    private(set) var text: String = ""
    /// The last recognition error, if any.
    private(set) var lastFailure: String?

    struct Line: Equatable, Sendable {
        let speaker: String
        let text: String
    }
    /// Finished utterances, most recent last.
    private(set) var history: [Line] = []
    private static let historyLimit = 2
    /// Whether the recogniser is attached to somebody's audio.
    var isListening: Bool { attachedTrack != nil }

    /// Recognised speech also feeds the summary, which needs a transcript
    /// even when captions are not being shown.
    var transcript: CallTranscript?
    /// Used to find the current speaker's track again when a task ends.
    var room: Room?

    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "Captions")

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var renderer: TrackAudioRenderer?
    private var attachedTrack: AudioTrack?
    private var currentTargetID: String?
    /// Each recognition task carries the generation it was started in.
    private var generation = 0
    private var consecutiveFailures = 0

    var isOn: Bool { mode != .off }

    func start() async {
        guard mode == .off else { return }

        let status = await Self.requestAuthorization()
        guard status == .authorized else {
            mode = .unavailable("Speech recognition permission was denied.")
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            mode = .unavailable("No speech recogniser available for this locale.")
            return
        }
        self.recognizer = recognizer
        // Prefer on-device: this is other people's audio, and the fallback
        // sends it to Apple.
        mode = recognizer.supportsOnDeviceRecognition ? .onDevice : .server
        logger.info("Captions started, mode: \(recognizer.supportsOnDeviceRecognition ? "on-device" : "server", privacy: .public)")
    }

    /// nonisolated deliberately: TCC calls the completion on its own XPC
    /// queue, and a closure written inside this @MainActor class inherits
    /// main-actor isolation — Swift 6 then asserts the executor and traps.
    private nonisolated static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Moves the current utterance into the caption history.
    private func archiveLine() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let line = Line(speaker: speakerName, text: trimmed)
        guard history.last != line else { return }
        history.append(line)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    /// Files what has been recognised so far.
    func flushNow() {
        flush()
    }

    private func flush() {
        guard let transcript, !text.isEmpty else { return }
        // The full text every time, not the new part: CallTranscript replaces
        // a line the new text extends, so repeated flushes of a growing
        // utterance collapse into one line instead of piling up fragments.
        transcript.append(speaker: speakerName.isEmpty ? "Someone" : speakerName, text: text)
    }

    func stop() {
        generation += 1
        consecutiveFailures = 0
        lastFailure = nil
        flush()
        history = []
        detach()
        recognizer = nil
        currentTargetID = nil
        speakerName = ""
        text = ""
        mode = .off
    }

    /// Points the recogniser at whoever is speaking now.
    func retarget(to participant: RemoteParticipant?, displayName: String) {
        guard isOn else { return }

        guard let participant,
              let publication = participant.audioTracks.first,
              let track = publication.track as? AudioTrack else {
            return
        }

        let id = RoomController.identityKey(for: participant)
        guard id != currentTargetID else { return }

        flush()
        archiveLine()
        detach()
        currentTargetID = id
        speakerName = displayName
        text = ""
        attach(to: track)
    }

    private func attach(to track: AudioTrack) {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        // Explicitly @Sendable for the same reason as requestAuthorization: a
        // closure written in a @MainActor method inherits that isolation, and
        // the recogniser calls back on its own queue, which traps under Swift
        // 6.
        generation += 1
        let mine = generation

        let handler: @Sendable (SFSpeechRecognitionResult?, Error?) -> Void = { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let failure = error?.localizedDescription
            let finished = error != nil || result?.isFinal == true
            Task { @MainActor in
                guard let self, mine == self.generation else { return }

                if let transcript, !transcript.isEmpty {
                    self.text = transcript
                    self.consecutiveFailures = 0
                    self.lastFailure = nil
                } else if let failure {
                    // A pause produces "No speech detected" as a matter of
                    // course, so one failure means nothing; only a run of
                    // them with nothing recognised in between is worth
                    // showing.
                    self.logger.info("Recognition ended: \(failure, privacy: .public)")
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures >= 3 { self.lastFailure = failure }
                }

                if finished {
                    // Recognition tasks end on their own — after a pause or a
                    // duration limit — so a fresh one is started to keep
                    // captions continuous.
                    self.restart()
                }
            }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: handler)

        // Capture the request itself rather than self: the audio callback is
        // Sendable and cannot touch main-actor state.
        nonisolated(unsafe) let sink = request
        let renderer = TrackAudioRenderer { buffer in
            sink.append(buffer)
        }
        self.renderer = renderer
        self.attachedTrack = track
        track.add(audioRenderer: renderer)
    }

    private func restart() {
        guard isOn else { return }
        let name = speakerName
        let track = attachedTrack ?? currentTrack()
        guard let track else { return }
        flush()
        archiveLine()
        detach()
        speakerName = name
        attach(to: track)
    }

    /// The audio of whoever is currently targeted, found afresh.
    private func currentTrack() -> AudioTrack? {
        guard let currentTargetID, let room else { return nil }
        for participant in room.remoteParticipants.values
        where RoomController.identityKey(for: participant) == currentTargetID {
            for publication in participant.audioTracks {
                if let track = publication.track as? AudioTrack { return track }
            }
        }
        return nil
    }

    private func detach() {
        if let renderer, let attachedTrack {
            attachedTrack.remove(audioRenderer: renderer)
        }
        renderer = nil
        attachedTrack = nil
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}

/// Bridges LiveKit's audio callback to a closure.
private final class TrackAudioRenderer: NSObject, AudioRenderer, @unchecked Sendable {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
        super.init()
    }

    func render(pcmBuffer: AVAudioPCMBuffer) {
        onBuffer(pcmBuffer)
    }
}
