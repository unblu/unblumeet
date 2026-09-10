import SwiftUI

/// One line of the lobby list.
struct ConferenceRow: View {
    let conference: ConversationData
    let onJoin: () -> Void

    @State private var hovering = false

    enum Column {
        static let host: CGFloat = 150
        static let people: CGFloat = 80
        static let age: CGFloat = 90
        /// Fixed so the header captions line up with the row columns.
        static let action: CGFloat = 48
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar

            Text(ConferenceDirectory.displayTopic(conference.topic))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(conference.hostName)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(width: Column.host, alignment: .leading)

            Label(Self.peopleText(conference.memberCount), systemImage: "person.2")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .frame(width: Column.people, alignment: .leading)

            Text(Self.ageText(conference.createdAt))
                .foregroundStyle(.secondary)
                .frame(width: Column.age, alignment: .leading)

            Circle()
                .fill(conference.isActive ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .help(conference.state ?? "unknown")

            Button("Join", action: onJoin)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(width: Column.action)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onJoin)
    }

    private var avatar: some View {
        Circle()
            .fill(Self.tint(for: conference.id).gradient)
            .frame(width: 26, height: 26)
            .overlay(
                Text(Self.initials(forTopic: ConferenceDirectory.displayTopic(conference.topic)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            )
    }

    nonisolated static func peopleText(_ count: Int) -> String {
        count == 1 ? "1 person" : "\(count) people"
    }

    nonisolated static func ageText(_ created: Date?) -> String {
        guard let created else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: created, relativeTo: Date())
    }

    nonisolated static func initials(forTopic topic: String) -> String {
        let words = topic.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "#" : letters.joined().uppercased()
    }

    /// Deterministic per conference so a row keeps its colour between
    /// refreshes.
    nonisolated static func tint(for id: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo]
        let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// Column captions, so the numbers in each row are self-explanatory.
struct ConferenceHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 26, height: 1)
            Text("Conference").frame(maxWidth: .infinity, alignment: .leading)
            Text("Host").frame(width: ConferenceRow.Column.host, alignment: .leading)
            Text("Members").frame(width: ConferenceRow.Column.people, alignment: .leading)
            Text("Created").frame(width: ConferenceRow.Column.age, alignment: .leading)
            Color.clear.frame(width: 7, height: 1)
            Color.clear.frame(width: ConferenceRow.Column.action, height: 1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }
}
