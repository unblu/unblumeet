import Foundation
import CryptoKit

/// Builds and signs LiveKit access tokens locally.
struct TokenSigner {
    let apiKey: String
    let apiSecret: String

    init(apiKey: String, apiSecret: String) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }

    func sign(identity: String, displayName: String, room: String, ttl: TimeInterval) -> String {
        sign(subject: identity, ttl: ttl, extra: ["name": displayName], video: [
            "room": room,
            "roomJoin": true,
            "canPublish": true,
            "canSubscribe": true,
            "canPublishData": true,
        ])
    }

    /// For asking the server what is going on, rather than joining anything.
    func signAdmin(ttl: TimeInterval) -> String {
        sign(subject: apiKey, ttl: ttl, extra: [:], video: [
            "roomList": true,
            "roomAdmin": true,
        ])
    }

    private func sign(subject: String, ttl: TimeInterval,
                      extra: [String: Any], video: [String: Any]) -> String {
        let now = Date().timeIntervalSince1970

        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        var payload: [String: Any] = [
            "iss": apiKey,
            "sub": subject,
            "nbf": now,
            "exp": now + ttl,
            "video": video,
        ]
        payload.merge(extra) { current, _ in current }

        let signingInput = Self.encode(header) + "." + Self.encode(payload)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: SymmetricKey(data: Data(apiSecret.utf8))
        )
        return signingInput + "." + Self.base64URL(Data(mac))
    }

    private static func encode(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
