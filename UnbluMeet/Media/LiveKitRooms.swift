import Foundation

/// Asks the LiveKit server who is actually in each room.
///
/// The lobby's member count comes from the Unblu conversation, which is the
/// assigned agent plus whoever created it — it never changes, and says nothing
/// about whether a call is happening.
struct LiveKitRooms: Sendable {
    let serverURL: String
    let signer: TokenSigner
    var session: URLSession = .shared

    /// Room name to participant count, for every room the server knows about.
    /// One request covers them all.
    func occupancy() async throws -> [String: Int] {
        guard let url = Self.httpURL(from: serverURL)?
            .appendingPathComponent("twirp/livekit.RoomService/ListRooms")
        else { return [:] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(signer.signAdmin(ttl: 300))", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, _) = try await session.data(for: request)
        return Self.occupancy(fromListRooms: data)
    }

    nonisolated static func occupancy(fromListRooms data: Data) -> [String: Int] {
        guard let result = try? JSONDecoder().decode(ListRoomsResult.self, from: data) else {
            return [:]
        }
        return (result.rooms ?? []).reduce(into: [:]) { counts, room in
            counts[room.name] = room.numParticipants
        }
    }

    /// The media URL is a websocket one; its API lives on http.
    nonisolated static func httpURL(from serverURL: String) -> URL? {
        var text = serverURL.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("wss://") { text = "https://" + text.dropFirst("wss://".count) }
        else if text.hasPrefix("ws://") { text = "http://" + text.dropFirst("ws://".count) }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }
}

private struct ListRoomsResult: Decodable {
    struct Room: Decodable {
        let name: String
        let numParticipants: Int

        /// Servers differ: this one emits the proto field names as they are,
        /// others the camel-cased form. Reading only one of them made every
        /// room look empty.
        private enum Keys: String, CodingKey {
            case name
            case snake = "num_participants"
            case camel = "numParticipants"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            name = try container.decode(String.self, forKey: .name)
            numParticipants = Self.count(container, .snake)
                ?? Self.count(container, .camel)
                ?? 0
        }

        /// A count can also arrive as a string, the way protobuf JSON renders
        /// wider integers.
        private static func count(_ container: KeyedDecodingContainer<Keys>,
                                  _ key: Keys) -> Int? {
            if let number = try? container.decode(Int.self, forKey: key) { return number }
            if let text = try? container.decode(String.self, forKey: key) { return Int(text) }
            return nil
        }
    }
    let rooms: [Room]?
}
