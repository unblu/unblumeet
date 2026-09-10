import Foundation

/// Codable mirrors of the Unblu Web API v4 responses this app consumes.

struct PersonData: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let displayName: String?
    let personType: String?
}

struct PersonResult: Codable, Sendable {
    let items: [PersonData]
}

struct ConversationData: Codable, Sendable, Identifiable, Equatable {
    struct Participant: Codable, Sendable, Equatable {
        let personId: String?
        let state: String?
    }
    struct BotParticipant: Codable, Sendable, Equatable {
        let personId: String?
    }

    let id: String
    let topic: String?
    let state: String?
    let creationTimestamp: Int64?
    let participants: [Participant]?
    let botParticipants: [BotParticipant]?
    /// The conversation's agent owner, as returned by the search — no extra
    /// request needed to show who hosts a conference.
    let recipient: PersonData?

    /// Agents plus UnbluMeet users.
    var memberCount: Int {
        (participants?.count ?? 0) + (botParticipants?.count ?? 0)
    }

    var createdAt: Date? {
        creationTimestamp.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }

    var hostName: String {
        recipient?.displayName ?? "—"
    }

    var isActive: Bool {
        state == "ACTIVE"
    }
}

struct ConversationResult: Codable, Sendable {
    let items: [ConversationData]
    let hasMoreItems: Bool?
}

struct MessageData: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let senderPersonId: String?
    let type: String?
    let text: String?
    let sendTimestamp: Int64?
}

struct MessageExportResult: Codable, Sendable {
    let items: [MessageData]
}

/// The rich, polymorphic read model returned by getMessage — distinct from
/// the flat ConversationHistoryMessageData the export returns, which carries
/// no file details at all.
struct FileMessageData: Codable, Sendable {
    struct DownloadLink: Codable, Sendable {
        let type: String
        let url: String
    }
    let id: String
    let fileName: String?
    let mimeType: String?
    let fileStoreId: String?
    let caption: String?
    let downloadLinks: [DownloadLink]?

    /// The Web API link, which accepts the same basic auth as everything else.
    var webApiURL: String? {
        downloadLinks?.first { $0.type == "WEB_API" }?.url
            ?? downloadLinks?.first?.url
    }

    var isImage: Bool { mimeType?.hasPrefix("image/") == true }
}

struct SendMessageResult: Codable, Sendable {
    let messageId: String
}
