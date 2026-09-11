import Foundation

/// A rolling window of connection measurements, for the panel's charts.
///
/// Bounded, because a call can run for hours and the charts only ever show the
/// recent past.
struct ConnectionHistory: Sendable, Equatable {
    struct Sample: Sendable, Equatable, Identifiable {
        let id: Int
        let at: Date
        let inbound: Double      // bits per second
        let outbound: Double
        let roundTrip: Double?   // seconds
        let loss: Double?        // percent
    }

    /// Two minutes at a sample every two seconds.
    static let capacity = 60

    private(set) var samples: [Sample] = []
    private var nextID = 0

    mutating func record(at: Date, inbound: Double, outbound: Double,
                         roundTrip: Double?, loss: Double?) {
        samples.append(Sample(id: nextID, at: at, inbound: inbound, outbound: outbound,
                              roundTrip: roundTrip, loss: loss))
        nextID += 1
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    mutating func clear() {
        samples.removeAll()
    }

    var isEmpty: Bool { samples.isEmpty }

    /// Headroom for a chart's axis, so a flat line does not fill the plot and
    /// a spike is not clipped.
    nonisolated static func upperBound(_ values: [Double], minimum: Double) -> Double {
        let peak = values.max() ?? 0
        return max(peak * 1.25, minimum)
    }

    var peakInbound: Double { samples.map(\.inbound).max() ?? 0 }
    var peakOutbound: Double { samples.map(\.outbound).max() ?? 0 }

    var averageRoundTrip: Double? {
        let values = samples.compactMap(\.roundTrip)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var worstLoss: Double? {
        samples.compactMap(\.loss).max()
    }
}
