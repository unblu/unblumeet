import Testing
import Foundation
import CryptoKit
@testable import UnbluMeet

private func decodeSegment(_ segment: String) -> [String: Any] {
    var s = segment.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
    while s.count % 4 != 0 { s += "=" }
    let data = Data(base64Encoded: s)!
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
}

@Test func tokenHasThreeSegments() {
    let jwt = TokenSigner(apiKey: "devkey", apiSecret: "secret")
        .sign(identity: "alice", displayName: "Alice", room: "room-1", ttl: 3600)
    #expect(jwt.split(separator: ".").count == 3)
}

@Test func tokenIsBase64URLWithoutPadding() {
    let jwt = TokenSigner(apiKey: "devkey", apiSecret: "secret")
        .sign(identity: "alice", displayName: "Alice", room: "room-1", ttl: 3600)
    #expect(!jwt.contains("="))
    #expect(!jwt.contains("+"))
    #expect(!jwt.contains("/"))
}

@Test func tokenCarriesLiveKitClaims() {
    let jwt = TokenSigner(apiKey: "devkey", apiSecret: "secret")
        .sign(identity: "alice", displayName: "Alice", room: "room-1", ttl: 3600)
    let parts = jwt.split(separator: ".").map(String.init)

    let header = decodeSegment(parts[0])
    #expect(header["alg"] as? String == "HS256")
    #expect(header["typ"] as? String == "JWT")

    let payload = decodeSegment(parts[1])
    #expect(payload["iss"] as? String == "devkey")
    #expect(payload["sub"] as? String == "alice")
    #expect(payload["name"] as? String == "Alice")

    let video = payload["video"] as! [String: Any]
    #expect(video["room"] as? String == "room-1")
    #expect(video["roomJoin"] as? Bool == true)
    #expect(video["canPublish"] as? Bool == true)
    #expect(video["canSubscribe"] as? Bool == true)
    #expect(video["canPublishData"] as? Bool == true)
}

@Test func expiryIsTTLSecondsAhead() {
    let jwt = TokenSigner(apiKey: "devkey", apiSecret: "secret")
        .sign(identity: "alice", displayName: "Alice", room: "room-1", ttl: 600)
    let payload = decodeSegment(jwt.split(separator: ".").map(String.init)[1])
    let exp = payload["exp"] as! Double
    let now = Date().timeIntervalSince1970
    #expect(exp > now + 590 && exp < now + 610)
}

@Test func signatureVerifiesAgainstSecret() {
    let jwt = TokenSigner(apiKey: "devkey", apiSecret: "topsecret")
        .sign(identity: "alice", displayName: "Alice", room: "room-1", ttl: 3600)
    let parts = jwt.split(separator: ".").map(String.init)
    let signingInput = Data((parts[0] + "." + parts[1]).utf8)

    let mac = HMAC<SHA256>.authenticationCode(
        for: signingInput,
        using: SymmetricKey(data: Data("topsecret".utf8))
    )
    let expected = Data(mac).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")

    #expect(parts[2] == expected)
}
