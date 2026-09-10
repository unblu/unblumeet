import Foundation
import Observation
import UniformTypeIdentifiers
import os

/// Chat in the Unblu conversation that backs this conference.
@Observable
@MainActor
final class ChatService {
    private(set) var messages: [MessageData] = []
    /// personId -> display name, resolved lazily and cached.
    private(set) var senderNames: [String: String] = [:]

    /// Resolved attachments, keyed by message id.
    private(set) var attachments: [String: Attachment] = [:]
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "Chat")

    struct Attachment: Sendable, Equatable {
        let fileName: String
        let mimeType: String
        let isImage: Bool
        let data: Data
    }

    /// Base64 in a JSON body inflates by about a third, and the whole thing
    /// travels in one request.
    static let maxAttachmentBytes = 5 * 1024 * 1024
    var error: String?

    private let client: UnbluClient
    private let conversationId: String
    private let botPersonId: String
    private var pollTask: Task<Void, Never>?

    init(client: UnbluClient, conversationId: String, botPersonId: String) {
        self.client = client
        self.conversationId = conversationId
        self.botPersonId = botPersonId
    }

    func send(_ text: String) async {
        // Both objects need Unblu's $_type discriminator, as sent in the
        // verified probe.
        struct TextData: Encodable {
            let dollarType = "TextPostMessageData"
            let type = "TEXT"
            let text: String
            enum CodingKeys: String, CodingKey {
                case dollarType = "$_type"
                case type, text
            }
        }
        struct Body: Encodable {
            let dollarType = "BotPostMessage"
            let conversationId: String
            let senderPersonId: String
            let messageData: TextData
            enum CodingKeys: String, CodingKey {
                case dollarType = "$_type"
                case conversationId, senderPersonId, messageData
            }
        }
        do {
            let _: SendMessageResult = try await client.post(
                "/bots/sendMessage",
                body: Body(conversationId: conversationId,
                           senderPersonId: botPersonId,
                           messageData: TextData(text: text))
            )
            await refresh()
        } catch {
            self.error = "\(error)"
        }
    }

    /// Sends a file inline as a data URL — Unblu takes the content in the
    /// message itself, so there is no separate upload step.
    func sendFile(named fileName: String, mimeType: String, data: Data, caption: String?) async {
        guard data.count <= Self.maxAttachmentBytes else {
            error = "\(fileName) is \(data.count / 1024 / 1024) MB; the limit is \(Self.maxAttachmentBytes / 1024 / 1024) MB."
            return
        }

        struct FileData: Encodable {
            let dollarType = "FilePostMessageData"
            let type = "FILE"
            let fileName: String
            let fileData: String
            let caption: String?
            let fallbackText: String
            enum CodingKeys: String, CodingKey {
                case dollarType = "$_type"
                case type, fileName, fileData, caption, fallbackText
            }
        }
        struct Body: Encodable {
            let dollarType = "BotPostMessage"
            let conversationId: String
            let senderPersonId: String
            let messageData: FileData
            enum CodingKeys: String, CodingKey {
                case dollarType = "$_type"
                case conversationId, senderPersonId, messageData
            }
        }

        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        do {
            let _: SendMessageResult = try await client.post(
                "/bots/sendMessage",
                body: Body(conversationId: conversationId,
                           senderPersonId: botPersonId,
                           messageData: FileData(fileName: fileName,
                                                 fileData: dataURL,
                                                 caption: caption?.isEmpty == false ? caption : nil,
                                                 fallbackText: fileName)))
            await refresh()
        } catch {
            self.error = "\(error)"
        }
    }

    /// Guesses a mime type from a file name, defaulting to binary.
    nonisolated static func mimeType(forFileNamed name: String) -> String {
        let ext = (name as NSString).pathExtension
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// System messages carry no text and no sender; they are noise in a chat
    /// pane, so they are filtered out here rather than in the view.
    private func refresh() async {
        struct Body: Encodable {
            let type = "MessageExportQuery"
            let limit = 200
            enum CodingKeys: String, CodingKey {
                case type = "$_type"
                case limit
            }
        }
        do {
            let result: MessageExportResult = try await client.post(
                "/conversationhistory/\(conversationId)/exportMessageLog", body: Body())
            messages = result.items
                .filter { $0.type != "SYSTEM" }
                .filter { $0.type == "FILE" || $0.text?.isEmpty == false }
                .sorted { ($0.sendTimestamp ?? 0) < ($1.sendTimestamp ?? 0) }
            error = nil
            await resolveSenderNames()
            await resolveAttachments()
        } catch {
            // Non-fatal: the call continues even if history is unavailable.
            self.error = "\(error)"
        }
    }

    /// Fetches file details and bytes for FILE messages not already cached.
    private func resolveAttachments() async {
        let pending = messages.filter { $0.type == "FILE" && attachments[$0.id] == nil }
        for message in pending {
            let detail: FileMessageData
            do {
                detail = try await client.get(
                    "/conversations/\(conversationId)/getMessage/\(message.id)")
            } catch {
                logger.error("getMessage \(message.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
            guard let path = detail.webApiURL else {
                logger.error("Message \(message.id, privacy: .public) has no download link")
                continue
            }
            let bytes: Data
            do {
                (bytes, _) = try await client.data(atServerPath: path)
            } catch {
                logger.error("Download of \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }

            attachments[message.id] = Attachment(
                fileName: detail.fileName ?? "file",
                mimeType: detail.mimeType ?? "application/octet-stream",
                isImage: detail.isImage,
                data: bytes)
        }
    }

    private func resolveSenderNames() async {
        let unknown = Set(messages.compactMap(\.senderPersonId))
            .subtracting(senderNames.keys)
        for personId in unknown {
            if let person: PersonData = try? await client.get("/persons/\(personId)/read") {
                senderNames[personId] = person.displayName ?? personId
            }
        }
    }
}
