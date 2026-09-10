import SwiftUI

/// The live call summary, built on device while the call runs.
struct SummaryPanel: View {
    let summary: SummaryService
    let width: CGFloat
    /// Speech recognition's own problem, if it has one.
    let recognitionIssue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: width)
        .background(.thinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text("Call summary").font(.headline)
            Spacer()
            if summary.state == .working {
                ProgressView().controlSize(.small)
            } else if summary.isRunning {
                // Says out loud that the microphone side is live.
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Listening — \(summary.heardWords) words recognised")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        switch summary.state {
        case .unavailable(let reason), .failed(let reason):
            VStack(alignment: .leading, spacing: 12) {
                Text(reason).foregroundStyle(.orange).textSelection(.enabled)
                Button("Try again") { summary.refreshNow() }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        case .off, .listening, .working:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if summary.overview.isEmpty && summary.items.isEmpty {
                        // heardWords is computed from a lock-guarded store
                        // that SwiftUI cannot observe, so this repaints on a
                        // timer.
                        TimelineView(.periodic(from: .now, by: 2)) { _ in
                            Text(waitingText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !summary.overview.isEmpty {
                        section("Overview") {
                            Text(summary.overview).textSelection(.enabled)
                        }
                    }

                    if !summary.items.isEmpty {
                        section("Decisions and actions") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(summary.items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("•")
                                        Text(item).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }

                    if !summary.recent.isEmpty {
                        section("Just now") {
                            Text(summary.recent)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private var waitingText: String {
        if let recognitionIssue { return recognitionIssue }
        let words = summary.heardWords
        if words == 0 {
            return "Listening. Nothing has been recognised yet — the summary starts once someone speaks."
        }
        return "Heard \(words) word\(words == 1 ? "" : "s") so far. The summary appears once there is enough to work with."
    }

    private func section(_ title: String, @ViewBuilder body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            body()
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { summary.refreshNow() }
                    .controlSize(.small)
                    .disabled(summary.state == .working)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        Self.plainText(overview: summary.overview, items: summary.items),
                        forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .controlSize(.small)
                .help("Copy the summary")
            }
            // Both halves are worth saying out loud: it is a draft, and the
            // audio never leaves the machine.
            Text("AI draft from on-device speech recognition — it can misattribute. Nothing leaves this Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusLine: String {
        guard let updated = summary.lastUpdated else { return "Listening…" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: updated, relativeTo: Date()))"
    }

    /// Takes values rather than the service: a nonisolated helper cannot read
    /// main-actor state, and the caller is already on the main actor.
    nonisolated static func plainText(overview: String, items: [String]) -> String {
        var parts: [String] = []
        if !overview.isEmpty { parts.append(overview) }
        if !items.isEmpty {
            parts.append(items.map { "• \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}
