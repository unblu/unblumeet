import SwiftUI
import Charts

/// What the connection is doing, for when a call is poor and watching it does
/// not say why.
struct ConnectionPanel: View {
    let inspector: ConnectionInspector
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitBody(inspector: inspector)
            Divider()
            footer
        }
        .frame(width: 860, height: 620)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
            Text("Connection").font(.headline)
            Spacer()
            summaryChips
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// The three numbers worth knowing before reading anything else.
    private var summaryChips: some View {
        let history = inspector.history
        return HStack(spacing: 8) {
            chip("down", ConnectionReport.format(bitsPerSecond: history.samples.last?.inbound))
            chip("up", ConnectionReport.format(bitsPerSecond: history.samples.last?.outbound))
            chip("rtt", ConnectionReport.milliseconds(history.samples.last?.roundTrip),
                 warning: ConnectionReport.isSlow(roundTrip: history.samples.last?.roundTrip))
            chip("loss", history.samples.last?.loss.map { String(format: "%.1f%%", $0) } ?? "—",
                 warning: (history.samples.last?.loss ?? 0) >= 1)
        }
    }

    private func chip(_ label: String, _ value: String, warning: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(warning ? .orange : .primary).monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var footer: some View {
        HStack {
            Text("Sampled every \(Int(ConnectionInspector.interval))s · \(inspector.history.samples.count) points")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(inspector.report.plainText, forType: .string)
            }
            Button("Refresh") { Task { await inspector.refresh() } }
            Button("Close", action: onClose).keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// Charts on the left, the numbers they come from on the right.
private struct HSplitBody: View {
    let inspector: ConnectionInspector

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ThroughputChart(history: inspector.history)
                    RoundTripChart(history: inspector.history)
                    LossChart(history: inspector.history)
                }
                .padding(16)
            }
            .frame(width: 430)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(inspector.report.sections) { section in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(section.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.lines) { line in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(line.label)
                                        .frame(width: 104, alignment: .leading)
                                        .foregroundStyle(.secondary)
                                    Text(line.value)
                                        .foregroundStyle(line.warning ? .orange : .primary)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }
                    if inspector.report.sections.isEmpty {
                        Text("Waiting for the first reading…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }
}

private struct ChartFrame<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(detail).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            content()
                .frame(height: 116)
                .padding(8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct ThroughputChart: View {
    let history: ConnectionHistory

    var body: some View {
        ChartFrame(title: "Throughput",
                   detail: "peak ↓ \(ConnectionReport.format(bitsPerSecond: history.peakInbound))  ↑ \(ConnectionReport.format(bitsPerSecond: history.peakOutbound))") {
            Chart {
                ForEach(history.samples) { sample in
                    AreaMark(x: .value("t", sample.at),
                             y: .value("down", sample.inbound / 1_000))
                        .foregroundStyle(by: .value("dir", "down"))
                        .opacity(0.35)
                    LineMark(x: .value("t", sample.at),
                             y: .value("up", sample.outbound / 1_000))
                        .foregroundStyle(by: .value("dir", "up"))
                }
            }
            .chartYScale(domain: 0 ... ConnectionHistory.upperBound(
                history.samples.flatMap { [$0.inbound / 1_000, $0.outbound / 1_000] }, minimum: 100))
            .chartYAxisLabel("kbps")
            .chartXAxis(.hidden)
            .chartForegroundStyleScale(["down": Color.accentColor, "up": Color.green])
        }
    }
}

private struct RoundTripChart: View {
    let history: ConnectionHistory

    var body: some View {
        ChartFrame(title: "Round trip",
                   detail: "avg \(ConnectionReport.milliseconds(history.averageRoundTrip))") {
            Chart(history.samples) { sample in
                if let rtt = sample.roundTrip {
                    LineMark(x: .value("t", sample.at), y: .value("ms", rtt * 1_000))
                        .foregroundStyle(Color.orange)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0 ... ConnectionHistory.upperBound(
                history.samples.compactMap { $0.roundTrip.map { $0 * 1_000 } }, minimum: 100))
            .chartYAxisLabel("ms")
            .chartXAxis(.hidden)
        }
    }
}

private struct LossChart: View {
    let history: ConnectionHistory

    var body: some View {
        ChartFrame(title: "Packet loss",
                   detail: history.worstLoss.map { String(format: "worst %.1f%%", $0) } ?? "none") {
            Chart(history.samples) { sample in
                if let loss = sample.loss {
                    BarMark(x: .value("t", sample.at), y: .value("%", loss))
                        .foregroundStyle(loss >= 1 ? Color.orange : Color.secondary)
                }
            }
            .chartYScale(domain: 0 ... ConnectionHistory.upperBound(
                history.samples.compactMap(\.loss), minimum: 2))
            .chartYAxisLabel("%")
            .chartXAxis(.hidden)
        }
    }
}
