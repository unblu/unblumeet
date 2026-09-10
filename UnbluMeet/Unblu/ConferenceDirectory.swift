import Foundation

/// The Unblu-side operations UnbluMeet needs: provisioning this user's bot
/// person, finding an agent to own conversations, and listing/creating
/// conferences.
struct ConferenceDirectory: Sendable {
    private let client: UnbluClient

    init(client: UnbluClient) {
        self.client = client
    }

    /// Marks a conversation as an UnbluMeet conference.
    static let topicMarker = "[UnbluMeet]"

    static func markedTopic(_ topic: String) -> String {
        "\(topicMarker) \(topic)"
    }

    static func displayTopic(_ topic: String?) -> String {
        guard let topic else { return "(no topic)" }
        guard topic.hasPrefix(topicMarker) else { return topic }
        return topic.dropFirst(topicMarker.count).trimmingCharacters(in: .whitespaces)
    }

    /// Stable per display name, so relaunching reuses the same bot person
    /// rather than accumulating duplicates.
    static func sourceId(for displayName: String) -> String {
        let slug = displayName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "unblumeet-\(slug)"
    }

    /// Idempotent by sourceId: repeated calls return the same person.
    func ensureBotPerson(displayName: String) async throws -> PersonData {
        // $_type is Unblu's polymorphic discriminator. Every probe that worked
        // sent it; do not drop it.
        struct Body: Encodable {
            let type = "PersonData"
            let sourceId: String
            let firstName: String
            let lastName: String
            enum CodingKeys: String, CodingKey {
                case type = "$_type"
                case sourceId, firstName, lastName
            }
        }
        let components = displayName.split(separator: " ", maxSplits: 1)
        let body = Body(sourceId: Self.sourceId(for: displayName),
                        firstName: String(components.first ?? "UnbluMeet"),
                        lastName: String(components.count > 1 ? components[1] : "User"))
        return try await client.post("/persons/createOrUpdateBot", body: body)
    }

    /// Conversations need a real agent as assignee — a bot is rejected with
    /// "Assignee must be an agent".
    func findAgentPerson() async throws -> PersonData {
        struct Body: Encodable { let limit: Int }
        let result: PersonResult = try await client.post("/persons/searchAgents", body: Body(limit: 20))
        guard let agent = result.items.first else {
            throw UnbluError.http(status: 404, message: "No agent person found in this account")
        }
        return agent
    }

    /// Only this app's conferences.
    func listConferences(limit: Int = 50) async throws -> [ConversationData] {
        struct Operator: Encodable {
            let dollarType = "ContainsStringOperator"
            let type = "CONTAINS"
            let value: String
            enum CodingKeys: String, CodingKey {
                case dollarType = "$_type"
                case type, value
            }
        }
        struct Filter: Encodable {
            let dollarType = "TopicConversationSearchFilter"
            let field = "TOPIC"
            let `operator`: Operator
            enum CodingKeys: String, CodingKey {
                case dollarType = "$_type"
                case field, `operator`
            }
        }
        struct Body: Encodable {
            let dollarType = "ConversationQuery"
            let limit: Int
            let searchFilters: [Filter]
            enum CodingKeys: String, CodingKey {
                case dollarType = "$_type"
                case limit, searchFilters
            }
        }
        let body = Body(limit: limit,
                        searchFilters: [Filter(operator: Operator(value: Self.topicMarker))])
        let result: ConversationResult = try await client.post("/conversations/search", body: body)
        return result.items
    }

    /// HEADLESS_INVITE is the agent-initiated engagement type; CHAT_REQUEST
    /// is rejected because it requires a visitor context person.
    func createConference(topic: String, agent: PersonData, bot: PersonData) async throws -> ConversationData {
        struct Participant: Encodable {
            let type = "ConversationCreationParticipantData"
            let personId: String
            let participationType: String
            enum CodingKeys: String, CodingKey {
                case type = "$_type"
                case personId, participationType
            }
        }
        struct CreateBody: Encodable {
            let type = "ConversationCreationData"
            let initialEngagementType: String
            let topic: String
            let participants: [Participant]
            enum CodingKeys: String, CodingKey {
                case type = "$_type"
                case initialEngagementType, topic, participants
            }
        }
        let conversation: ConversationData = try await client.post(
            "/conversations/create",
            body: CreateBody(initialEngagementType: "HEADLESS_INVITE",
                             topic: Self.markedTopic(topic),
                             participants: [Participant(personId: agent.id,
                                                        participationType: "ASSIGNED_AGENT")])
        )
        try await addParticipant(conversationId: conversation.id, personId: bot.id)
        return conversation
    }

    func addParticipant(conversationId: String, personId: String) async throws {
        struct Body: Encodable { let personId: String }
        try await client.postIgnoringResponse("/conversations/\(conversationId)/addParticipant",
                                              body: Body(personId: personId))
    }
}
