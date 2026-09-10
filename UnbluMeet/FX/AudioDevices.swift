import Foundation

/// Turns the audio device module's raw list into something a menu can show.
enum AudioDevices {
    /// The id the audio device module uses for "whatever the system is set to".
    static let systemDefaultID = "default"

    struct Entry: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
    }

    nonisolated static func entries(from devices: [(id: String, name: String)]) -> [Entry] {
        var entries: [Entry] = []
        var seenIDs: Set<String> = []
        var nameCounts: [String: Int] = [:]

        for device in devices where !seenIDs.contains(device.id) {
            seenIDs.insert(device.id)

            if device.id == systemDefaultID {
                // Named, not just "System default": which device that
                // currently means is the thing people want to know.
                let label = device.name.isEmpty
                    ? "System default"
                    : "System default (\(device.name))"
                entries.insert(Entry(id: device.id, label: label), at: 0)
                continue
            }

            let count = (nameCounts[device.name] ?? 0) + 1
            nameCounts[device.name] = count
            entries.append(Entry(id: device.id,
                                 label: count == 1 ? device.name : "\(device.name) (\(count))"))
        }
        return entries
    }

    /// The id a picker should show.
    nonisolated static func resolvedSelection(current: String,
                                              activeID: String,
                                              entries: [Entry]) -> String {
        if entries.contains(where: { $0.id == current }), !current.isEmpty { return current }
        if entries.contains(where: { $0.id == activeID }), !activeID.isEmpty { return activeID }
        return entries.first?.id ?? ""
    }
}
