import Foundation

/// What the Unblu side of a call looks like, for the connection panel.
///
/// The media half says nothing about the conversation the call belongs to —
/// whether the server is answering, who owns it, or whether Unblu itself has a
/// call running in the same room.
struct UnbluStatusProbe: Sendable {
    let client: UnbluClient
    let host: String
    let conversationId: String
    let identity: String

    func status() async -> ConnectionReport.Section {
        var lines: [ConnectionReport.Line] = [
            .init(id: "host", label: "Server", value: host),
        ]

        let started = Date()
        let conversation: ConversationData? = try? await client.get(
            "/conversations/\(conversationId)/read")
        let elapsed = Date().timeIntervalSince(started)

        if let conversation {
            lines.append(.init(id: "api", label: "API",
                               value: "answering  \(ConnectionReport.milliseconds(elapsed))",
                               warning: Self.isSluggish(elapsed)))
            lines.append(.init(id: "topic", label: "Conversation",
                               value: ConferenceDirectory.displayTopic(conversation.topic)))
            lines.append(.init(id: "state", label: "State",
                               value: conversation.state ?? "—",
                               warning: conversation.state != "ACTIVE"))
            lines.append(.init(id: "owner", label: "Owner", value: conversation.hostName))
        } else {
            lines.append(.init(id: "api", label: "API", value: "no answer", warning: true))
        }

        lines.append(.init(id: "convid", label: "Room / id", value: conversationId))
        let exact = !identity.contains("~")
        lines.append(.init(id: "person", label: "Joined as",
                           value: identity + (exact ? "  (exact — visible to Unblu)" : "  (per session)")))

        lines.append(.init(id: "unblucall", label: "Unblu call",
                           value: await unbluCallSummary()))
        return ConnectionReport.Section(id: "unblu", title: "Unblu", lines: lines)
    }

    /// Whether the collaboration server has a call of its own on this
    /// conversation. It names its LiveKit room after the conversation id too,
    /// so such a call shares this room and its participants arrive here.
    private func unbluCallSummary() async -> String {
        struct Operator: Encodable {
            let dollarType = "EqualsStringOperator"
            let type = "EQUALS"
            let value: String
            enum CodingKeys: String, CodingKey { case dollarType = "$_type"; case type, value }
        }
        struct Filter: Encodable {
            let dollarType = "ConversationIdCallSearchFilter"
            let field = "CONVERSATION_ID"
            let `operator`: Operator
            enum CodingKeys: String, CodingKey { case dollarType = "$_type"; case field, `operator` }
        }
        struct Body: Encodable {
            let dollarType = "CallQuery"
            let limit = 5
            let searchFilters: [Filter]
            enum CodingKeys: String, CodingKey { case dollarType = "$_type"; case limit, searchFilters }
        }

        guard let result: CallResult = try? await client.post(
            "/calls/search",
            body: Body(searchFilters: [Filter(operator: Operator(value: conversationId))]))
        else { return "unknown" }

        return Self.describeCalls(result.items ?? [])
    }

    /// A call with no end timestamp is still running.
    nonisolated static func describeCalls(_ calls: [CallData]) -> String {
        let live = calls.filter { $0.endTimestamp == nil }
        guard !live.isEmpty else {
            return calls.isEmpty ? "none" : "none now (\(calls.count) earlier)"
        }
        let types = live.compactMap(\.serviceProviderType).joined(separator: ", ")
        return types.isEmpty ? "\(live.count) running" : "\(live.count) running — \(types)"
    }

    /// A conversation read is a small request; a fifth of a second for one
    /// means the rest of the app will feel slow too.
    nonisolated static func isSluggish(_ seconds: TimeInterval) -> Bool {
        seconds > 0.5
    }
}

struct CallData: Codable, Sendable {
    let id: String?
    let conversationId: String?
    let serviceProviderType: String?
    let initiationTimestamp: Int64?
    let endTimestamp: Int64?
}

struct CallResult: Codable, Sendable {
    let items: [CallData]?
}
