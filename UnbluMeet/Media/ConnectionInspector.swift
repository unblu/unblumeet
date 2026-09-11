import Foundation
import Observation
import LiveKit

/// Collects what the SDK knows about the connection into a readable report.
///
/// Rates are computed from the change in byte counters between polls, because
/// the statistics are cumulative totals.
@Observable
@MainActor
final class ConnectionInspector {
    private(set) var report = ConnectionReport()
    private(set) var history = ConnectionHistory()
    private(set) var isRunning = false

    private var previousBytes: [String: (value: UInt64, at: Date)] = [:]
    private var task: Task<Void, Never>?
    private weak var controller: RoomController?
    /// Set by the conference, which knows about the Unblu side.
    var unblu: UnbluStatusProbe?

    static let interval: TimeInterval = 2

    func start(controller: RoomController) {
        self.controller = controller
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        previousBytes = [:]
    }

    func refresh() async {
        guard let controller else { return }
        let room = controller.room

        // Statistics only arrive for tracks asked to report them.
        for participant in room.remoteParticipants.values {
            for publication in participant.videoTracks {
                if let track = publication.track { await track.set(reportStatistics: true) }
            }
        }
        for publication in room.localParticipant.trackPublications.values {
            if let track = publication.track { await track.set(reportStatistics: true) }
        }

        // Order is reading order: the conversation and the connection first,
        // participants after. Appending Unblu last put it below eight
        // participants and out of sight.
        var sections: [ConnectionReport.Section] = []
        sections.append(serverSection(room))
        if let unblu { sections.append(await unblu.status()) }
        if let transport = transportSection(room) { sections.append(transport) }
        sections.append(localSection(room))
        sections.append(contentsOf: remoteSections(room))
        report = ConnectionReport(sections: sections)
        recordSample(room)
    }

    /// Totals across every track, for the charts.
    private func recordSample(_ room: Room) {
        var inbound: Double = 0
        var outbound: Double = 0
        var lost: UInt64 = 0
        var received: UInt64 = 0

        for participant in room.remoteParticipants.values {
            for publication in participant.trackPublications.values {
                guard let stats = publication.track?.statistics?.inboundRtpStream.first else { continue }
                inbound += bitsPerSecond("hist-in-\(publication.sid.stringValue)",
                                         bytes: stats.bytesReceived) ?? 0
                lost += UInt64(stats.packetsLost ?? 0)
                received += stats.packetsReceived ?? 0
            }
        }
        for publication in room.localParticipant.trackPublications.values {
            guard let stats = publication.track?.statistics?.outboundRtpStream.first else { continue }
            outbound += bitsPerSecond("hist-out-\(publication.sid.stringValue)",
                                      bytes: stats.bytesSent) ?? 0
        }

        history.record(at: Date(), inbound: inbound, outbound: outbound,
                       roundTrip: currentRoundTrip(room),
                       loss: ConnectionReport.lossPercent(lost: lost, received: received))
    }

    private func currentRoundTrip(_ room: Room) -> Double? {
        let tracks = room.localParticipant.trackPublications.values.compactMap(\.track)
            + room.remoteParticipants.values.flatMap { $0.trackPublications.values.compactMap(\.track) }
        for stats in tracks.compactMap(\.statistics) {
            if let pair = stats.iceCandidatePair.first(where: { $0.nominated == true })
                ?? stats.iceCandidatePair.first,
               let rtt = pair.currentRoundTripTime {
                return rtt
            }
        }
        return nil
    }

    private func serverSection(_ room: Room) -> ConnectionReport.Section {
        ConnectionReport.Section(id: "server", title: "Server", lines: [
            .init(id: "state", label: "State", value: "\(room.connectionState)"),
            .init(id: "url", label: "URL", value: room.url ?? "—"),
            .init(id: "room", label: "Room", value: room.name ?? "—"),
            .init(id: "sid", label: "Room SID", value: room.sid?.stringValue ?? "—"),
            .init(id: "version", label: "Version", value: room.serverVersion ?? "—"),
            .init(id: "region", label: "Region", value: room.serverRegion ?? "—"),
            .init(id: "node", label: "Node", value: room.serverNodeId ?? "—"),
            .init(id: "identity", label: "Identity",
                  value: room.localParticipant.identity?.stringValue ?? "—"),
        ])
    }

    /// The ICE pair carrying the media, which is the thing to look at when a
    /// call is fine on paper and bad in practice.
    private func transportSection(_ room: Room) -> ConnectionReport.Section? {
        let tracks = room.localParticipant.trackPublications.values.compactMap(\.track)
            + room.remoteParticipants.values.flatMap { $0.trackPublications.values.compactMap(\.track) }
        guard let stats = tracks.compactMap(\.statistics).first(where: { !$0.iceCandidatePair.isEmpty }),
              let pair = stats.iceCandidatePair.first(where: { $0.nominated == true })
                ?? stats.iceCandidatePair.first
        else { return nil }

        let relayed = ConnectionReport.isRelayed(stats.localIceCandidate)
            || ConnectionReport.isRelayed(stats.remoteIceCandidate)
        let endToEnd = room.e2eeManager != nil
        let transport = stats.transportStats

        return ConnectionReport.Section(id: "ice", title: "Transport", lines: [
            .init(id: "path", label: "Media path",
                  value: ConnectionReport.describePath(local: stats.localIceCandidate,
                                                      remote: stats.remoteIceCandidate),
                  warning: relayed),
            .init(id: "encryption", label: "Encryption",
                  value: ConnectionReport.describeEncryption(
                      dtlsState: transport?.dtlsState.map { "\($0)" },
                      cipher: transport?.dtlsCipher,
                      tlsVersion: transport?.tlsVersion,
                      endToEnd: endToEnd)),
            .init(id: "e2ee", label: "Server can read",
                  value: ConnectionReport.isReadableByServer(endToEnd: endToEnd)
                      ? "yes — no end-to-end encryption" : "no",
                  warning: ConnectionReport.isReadableByServer(endToEnd: endToEnd)),
            .init(id: "pairstate", label: "ICE pair", value: pair.state.map { "\($0)" } ?? "—"),
            .init(id: "rtt", label: "Round trip",
                  value: ConnectionReport.milliseconds(pair.currentRoundTripTime),
                  warning: ConnectionReport.isSlow(roundTrip: pair.currentRoundTripTime)),
            .init(id: "local", label: "Local candidate",
                  value: ConnectionReport.describeCandidate(stats.localIceCandidate)),
            .init(id: "remote", label: "Remote candidate",
                  value: ConnectionReport.describeCandidate(stats.remoteIceCandidate),
                  warning: relayed),
            .init(id: "outbit", label: "Available up",
                  value: pair.availableOutgoingBitrate.map {
                      ConnectionReport.bitrate(bytes: UInt64($0 / 8), over: 1)
                  } ?? "—"),
            .init(id: "sent", label: "Sent",
                  value: rate("ice-sent", bytes: pair.bytesSent)),
            .init(id: "received", label: "Received",
                  value: rate("ice-received", bytes: pair.bytesReceived)),
        ])
    }

    private func localSection(_ room: Room) -> ConnectionReport.Section {
        var lines: [ConnectionReport.Line] = [
            .init(id: "quality", label: "Quality",
                  value: ConnectionReport.describe(room.localParticipant.connectionQuality),
                  warning: ConnectionReport.isPoor(room.localParticipant.connectionQuality)),
        ]

        for publication in room.localParticipant.trackPublications.values {
            guard let track = publication.track, let outbound = track.statistics?.outboundRtpStream.first
            else { continue }
            let name = "\(publication.source)"
            var value = rate("out-\(publication.sid.stringValue)", bytes: outbound.bytesSent)
            if let width = outbound.frameWidth, let height = outbound.frameHeight {
                value += "  \(width)×\(height)"
            }
            if let fps = outbound.framesPerSecond { value += String(format: "  %.0f fps", fps) }
            let limited = outbound.qualityLimitationReason.map { "\($0)" }
            if let limited, limited != "none" { value += "  limited: \(limited)" }
            lines.append(.init(id: "out-\(name)", label: name.capitalized, value: value,
                               warning: limited != nil && limited != "none"))
        }
        return ConnectionReport.Section(id: "local", title: "Publishing", lines: lines)
    }

    private func remoteSections(_ room: Room) -> [ConnectionReport.Section] {
        room.remoteParticipants.values
            .sorted { RoomController.identityKey(for: $0) < RoomController.identityKey(for: $1) }
            .map { participant in
                let identity = RoomController.identityKey(for: participant)
                var lines: [ConnectionReport.Line] = [
                    .init(id: "q-\(identity)", label: "Quality",
                          value: ConnectionReport.describe(participant.connectionQuality),
                          warning: ConnectionReport.isPoor(participant.connectionQuality)),
                ]

                for publication in participant.trackPublications.values {
                    guard let remote = publication as? RemoteTrackPublication else { continue }
                    guard remote.isSubscribed, let track = remote.track,
                          let inbound = track.statistics?.inboundRtpStream.first
                    else {
                        lines.append(.init(id: "sub-\(publication.sid.stringValue)",
                                           label: "\(publication.source)",
                                           value: remote.isSubscribed ? "no statistics yet" : "not subscribed"))
                        continue
                    }

                    var value = rate("in-\(publication.sid.stringValue)", bytes: inbound.bytesReceived)
                    if let width = inbound.frameWidth, let height = inbound.frameHeight {
                        value += "  \(width)×\(height)"
                    }
                    if let fps = inbound.framesPerSecond { value += String(format: "  %.0f fps", fps) }
                    let lost = inbound.packetsLost.map { UInt64($0) }
                    let loss = ConnectionReport.lossText(lost: lost, received: inbound.packetsReceived)
                    value += "  loss \(loss)"
                    if let jitter = inbound.jitter { value += "  jitter \(ConnectionReport.milliseconds(jitter))" }
                    if let freezes = inbound.freezeCount, freezes > 0 { value += "  freezes \(freezes)" }

                    lines.append(.init(id: "in-\(publication.sid.stringValue)",
                                       label: "\(publication.source)",
                                       value: value,
                                       warning: ConnectionReport.isLossy(
                                           lost: lost, received: inbound.packetsReceived)))
                }

                return ConnectionReport.Section(id: identity, title: identity, lines: lines)
            }
    }

    /// Bytes are cumulative, so a rate needs the previous reading.
    private func bitsPerSecond(_ key: String, bytes: UInt64?) -> Double? {
        guard let bytes else { return nil }
        let now = Date()
        defer { previousBytes[key] = (bytes, now) }
        guard let previous = previousBytes[key], bytes >= previous.value else { return nil }
        let seconds = now.timeIntervalSince(previous.at)
        guard seconds > 0 else { return nil }
        return Double(bytes - previous.value) * 8 / seconds
    }

    private func rate(_ key: String, bytes: UInt64?) -> String {
        ConnectionReport.format(bitsPerSecond: bitsPerSecond(key, bytes: bytes))
    }
}
