import Testing
import Foundation
@testable import UnbluMeet

private func normalised(_ text: String) -> String {
    UnbluClient.normalised(URL(string: text)!).absoluteString
}

@Test func aBareHostGetsTheApiRoot() {
    // The most likely thing to type, and it 404s on every call.
    #expect(normalised("https://unblu.example.com") == "https://unblu.example.com/app/rest/v4")
    #expect(normalised("http://localhost:7777") == "http://localhost:7777/app/rest/v4")
}

@Test func aTrailingSlashIsNotDoubled() {
    #expect(normalised("https://unblu.example.com/") == "https://unblu.example.com/app/rest/v4")
}

@Test func anAddressEndingInAppGetsTheRest() {
    #expect(normalised("https://unblu.example.com/app") == "https://unblu.example.com/app/rest/v4")
}

@Test func acompleteAddressIsLeftAlone() {
    #expect(normalised("https://unblu.example.com/app/rest/v4") == "https://unblu.example.com/app/rest/v4")
    #expect(normalised("http://localhost:7777/app/rest/v4") == "http://localhost:7777/app/rest/v4")
}

@Test func aDeliberateOtherVersionIsRespected() {
    // Somebody pointing at v3 on purpose should not be silently upgraded.
    #expect(normalised("https://unblu.example.com/app/rest/v3") == "https://unblu.example.com/app/rest/v3")
}

@Test func aServerBehindAPathPrefixStillWorks() {
    #expect(normalised("https://example.com/unblu") == "https://example.com/unblu/app/rest/v4")
}

@Test func theOriginIsStillRecoverableForDownloadLinks() {
    // What matters is the URL a server-rooted download link resolves to.
    let base = UnbluClient.normalised(URL(string: "https://unblu.example.com")!)
    #expect(UnbluClient.downloadURL(for: "/app/rest/fileDownload/x", base: base)?.absoluteString
            == "https://unblu.example.com/app/rest/fileDownload/x")
}
