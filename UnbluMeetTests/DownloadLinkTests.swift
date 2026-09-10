import Testing
import Foundation
@testable import UnbluMeet

private let base = URL(string: "https://unblu.example.com/app/rest/v4")!

@Test func anAbsoluteLinkIsUsedAsGiven() {
    // Some servers return the whole URL; prefixing the origin onto it produced
    // https://host/https://host/... which fails silently and leaves chat
    // images blank.
    let link = "https://unblu.example.com/app/rest/fileDownload/abc123"
    #expect(UnbluClient.downloadURL(for: link, base: base)?.absoluteString == link)
}

@Test func aServerRootedPathIsJoinedToTheOrigin() {
    #expect(UnbluClient.downloadURL(for: "/app/rest/fileDownload/abc123", base: base)?.absoluteString
            == "https://unblu.example.com/app/rest/fileDownload/abc123")
}

@Test func aLinkOnAnotherHostIsRespected() {
    let link = "https://files.example.net/download/abc123"
    #expect(UnbluClient.downloadURL(for: link, base: base)?.absoluteString == link)
}

@Test func aLocalServerBehindAPortStillResolves() {
    let local = URL(string: "http://localhost:7777/app/rest/v4")!
    #expect(UnbluClient.downloadURL(for: "/app/rest/fileDownload/x", base: local)?.absoluteString
            == "http://localhost:7777/app/rest/fileDownload/x")
}
