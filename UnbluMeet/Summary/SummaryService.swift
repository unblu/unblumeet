import Foundation
import Observation
import FoundationModels
import os

/// What the model is asked to produce each cycle.
@Generable
struct CallExtraction {
    @Guide(description: "One sentence on what was just discussed.")
    var recent: String
    @Guide(description: "Decisions and action items stated in THIS excerpt only, each one self-contained and naming who is responsible if it was said. Empty if none.")
    var newItems: [String]
}

@Generable
struct CallOverview {
    @Guide(description: "Two or three sentences describing what this call is about, for someone joining late.")
    var text: String
}

/// A running summary of the call, built on device.
@Observable
@MainActor
final class SummaryService {
    enum State: Equatable {
        case off
        case unavailable(String)
        case listening
        case working
        case failed(String)
    }

    private(set) var state: State = .off
    private(set) var overview = ""
    private(set) var recent = ""
    private(set) var items: [String] = []
    private(set) var lastUpdated: Date?

    let transcript = CallTranscript()

    /// How often new speech is folded in.
    nonisolated static let interval: TimeInterval = 45
    /// The overview is rewritten from the item list, not from transcript, and
    /// only every so often: it is the one part that genuinely re-reads
    /// itself.
    nonisolated static let overviewEveryCycles = 7
    /// About one spoken sentence.
    nonisolated static let minimumNewWords = 12
    /// Well under the measured ~3,100-word ceiling, leaving room for output.
    nonisolated static let windowWordLimit = 1_200

    /// How often the transcript is checked.
    nonisolated static let pollInterval: TimeInterval = 10

    private var lastGeneratedAt: Date?
    private var cursor: TimeInterval = 0
    private var cyclesSinceOverview = 0
    private var loop: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "Summary")

    var isRunning: Bool { loop != nil }

    /// How much speech has been recognised.
    var heardWords: Int { CallTranscript.wordCount(transcript.lines(after: 0)) }

    func start() {
        guard loop == nil else { return }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            state = .unavailable(Self.explain(reason))
            return
        }

        state = .listening
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollInterval))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        state = .off
    }

    /// Runs a cycle now, for the Refresh button.
    func refreshNow() {
        Task { await tick(force: true) }
    }

    private func tick(force: Bool = false) async {
        guard state != .working else { return }

        let fresh = transcript.lines(after: cursor)
        guard !fresh.isEmpty else { return }

        if !force {
            guard CallTranscript.wordCount(fresh) >= Self.minimumNewWords else { return }
            if let last = lastGeneratedAt, Date().timeIntervalSince(last) < Self.interval { return }
        }

        let window = CallTranscript.trimmed(fresh, toWords: Self.windowWordLimit)
        cursor = window.last?.at ?? cursor

        state = .working
        defer { if state == .working { state = .listening } }

        do {
            let extraction = try await extract(from: window)
            recent = extraction.recent
            for item in extraction.newItems {
                guard Self.isWorthKeeping(item), !Self.isDuplicate(item, of: items) else { continue }
                items.append(item)
            }
            lastUpdated = Date()
            lastGeneratedAt = lastUpdated

            cyclesSinceOverview += 1
            if overview.isEmpty || cyclesSinceOverview >= Self.overviewEveryCycles {
                cyclesSinceOverview = 0
                overview = (try? await makeOverview()) ?? overview
            }
        } catch {
            logger.error("Summary cycle failed: \(error.localizedDescription, privacy: .public)")
            state = .failed("\(error)")
        }
    }

    private func extract(from window: [TranscriptLine]) async throws -> CallExtraction {
        let session = LanguageModelSession(instructions: """
            You watch a live call. From the excerpt given, extract only decisions and \
            action items stated in THAT excerpt. Make each item understandable on its own, \
            naming the person responsible when it was said. Do not repeat items already \
            listed as known. Never invent anything.
            """)
        // Only the tail of the list: it exists to prevent repeats, and
        // passing hundreds of items back would recreate the bottleneck this
        // design avoids.
        let known = items.suffix(8).joined(separator: "; ")
        let prompt = """
            Known already (do not repeat): \(known.isEmpty ? "nothing yet" : known)

            Excerpt:
            \(CallTranscript.format(window))
            """
        do {
            return try await session.respond(to: prompt, generating: CallExtraction.self).content
        } catch let error as LanguageModelSession.GenerationError {
            // Halve and retry rather than fail the panel: the ceiling depends
            // on locale and model revision, so a measured limit is not a
            // guarantee.
            if case .exceededContextWindowSize = error {
                let smaller = CallTranscript.trimmed(window, toWords: Self.windowWordLimit / 2)
                let retry = LanguageModelSession(instructions: "Extract decisions and action items. Never invent anything.")
                return try await retry.respond(to: CallTranscript.format(smaller),
                                               generating: CallExtraction.self).content
            }
            throw error
        }
    }

    private func makeOverview() async throws -> String {
        let session = LanguageModelSession(instructions: """
            You describe an ongoing call for someone about to join it. Be factual and \
            terse. Use only what is listed. Never invent anything.
            """)
        let list = items.suffix(30).joined(separator: "\n")
        return try await session.respond(to: "What has happened on this call:\n\(list)",
                                         generating: CallOverview.self).content.text
    }

    func reset() {
        transcript.clear()
        items = []
        overview = ""
        recent = ""
        cursor = 0
        cyclesSinceOverview = 0
        lastUpdated = nil
        lastGeneratedAt = nil
    }

    /// A coarse backstop against fragments.
    nonisolated static func isWorthKeeping(_ item: String) -> Bool {
        item.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).count >= 5
    }

    nonisolated static func normalise(_ item: String) -> String {
        item.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The model re-states items in slightly different words, so exact
    /// matching lets duplicates through.
    nonisolated static func isDuplicate(_ item: String, of existing: [String]) -> Bool {
        let candidate = Set(normalise(item).split(separator: " "))
        guard !candidate.isEmpty else { return true }
        for other in existing {
            let words = Set(normalise(other).split(separator: " "))
            guard !words.isEmpty else { continue }
            let shared = candidate.intersection(words).count
            if Double(shared) / Double(min(candidate.count, words.count)) >= 0.8 { return true }
        }
        return false
    }

    nonisolated static func explain(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This Mac does not support Apple Intelligence, so the on-device model is unavailable."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in System Settings to use the call summary."
        case .modelNotReady:
            "The on-device model is still downloading. Try again shortly."
        @unknown default:
            "The on-device model is unavailable."
        }
    }
}
