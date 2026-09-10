import Testing
import Foundation
@testable import UnbluMeet

@Test func originStripsTheApiPathFromTheBaseURL() {
    // Download links are rooted at the server, not under /app/rest/v4.
    let base = URL(string: "http://localhost:7777/app/rest/v4")!
    #expect(UnbluClient.origin(of: base).absoluteString == "http://localhost:7777/")
}

@Test func originHandlesABareHost() {
    let base = URL(string: "http://192.168.1.168:7777")!
    #expect(UnbluClient.origin(of: base).absoluteString.hasPrefix("http://192.168.1.168:7777"))
}

@Test func mimeTypeIsGuessedFromTheExtension() {
    #expect(ChatService.mimeType(forFileNamed: "shot.png") == "image/png")
    #expect(ChatService.mimeType(forFileNamed: "notes.pdf") == "application/pdf")
}

@Test func unknownExtensionsFallBackToBinary() {
    #expect(ChatService.mimeType(forFileNamed: "thing.zzzz") == "application/octet-stream")
    #expect(ChatService.mimeType(forFileNamed: "noextension") == "application/octet-stream")
}

@Test func webApiLinkIsPreferredOverAgentDesk() {
    // Both links point at the same file, but only the Web API one accepts the
    // basic auth the client already has.
    let json = """
    {"id":"m1","fileName":"probe.png","mimeType":"image/png",
     "fileStoreId":"abc","caption":null,
     "downloadLinks":[{"type":"AGENT_DESK","url":"/app/fileDownload/abc"},
                      {"type":"WEB_API","url":"/app/rest/fileDownload/abc"}]}
    """
    let detail = try! JSONDecoder().decode(FileMessageData.self, from: Data(json.utf8))
    #expect(detail.webApiURL == "/app/rest/fileDownload/abc")
    #expect(detail.isImage)
}

@Test func nonImageMimeTypesAreNotTreatedAsImages() {
    let json = """
    {"id":"m2","fileName":"notes.pdf","mimeType":"application/pdf",
     "fileStoreId":"def","caption":null,"downloadLinks":[]}
    """
    let detail = try! JSONDecoder().decode(FileMessageData.self, from: Data(json.utf8))
    #expect(!detail.isImage)
    #expect(detail.webApiURL == nil)
}

@Test func virtualCamerasAreRecognised() {
    // A virtual camera can win AVCaptureDevice.default and then produce no
    // frames, which is indistinguishable from a broken camera.
    #expect(CameraCapture.isVirtualName("OBS Virtual Camera"))
    #expect(CameraCapture.isVirtualName("Camo Camera"))
    #expect(!CameraCapture.isVirtualName("FaceTime HD Camera"))
    #expect(!CameraCapture.isVirtualName("Studio Display Camera"))
}

@Test func aContinuityCameraIsNotTreatedAsVirtual() {
    // It is a real camera — just an unreliable default, since it needs the
    // phone nearby and awake.
    #expect(!CameraCapture.isVirtualName("DaoPhone14Max Camera"))
    #expect(!CameraCapture.isVirtualName("iPhone Air Camera"))
}
