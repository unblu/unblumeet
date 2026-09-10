import Testing
import Foundation
@testable import UnbluMeet

private struct Probe: Codable, Equatable { let limit: Int }
private struct Reply: Codable, Equatable { let id: String }

private func makeClient() -> UnbluClient {
    UnbluClient(baseURL: URL(string: "http://localhost:7777/app/rest/v4")!,
                username: "superadmin",
                password: "superadmin",
                session: StubURLProtocol.makeSession())
}

@Test func postSendsBasicAuthHeader() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (200, Data(#"{"id":"x"}"#.utf8)) }

    let _: Reply = try await makeClient().post("/conversations/search", body: Probe(limit: 2))

    let header = StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
    let expected = "Basic " + Data("superadmin:superadmin".utf8).base64EncodedString()
    #expect(header == expected)
}

@Test func postUsesPostMethodAndJSONContentType() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (200, Data(#"{"id":"x"}"#.utf8)) }

    let _: Reply = try await makeClient().post("/conversations/search", body: Probe(limit: 2))

    #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
    #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
}

@Test func postAppendsPathToBaseURL() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (200, Data(#"{"id":"x"}"#.utf8)) }

    let _: Reply = try await makeClient().post("/conversations/search", body: Probe(limit: 2))

    #expect(StubURLProtocol.lastRequest?.url?.absoluteString
            == "http://localhost:7777/app/rest/v4/conversations/search")
}

@Test func postEncodesTheBody() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (200, Data(#"{"id":"x"}"#.utf8)) }

    let _: Reply = try await makeClient().post("/conversations/search", body: Probe(limit: 7))

    let sent = try #require(StubURLProtocol.lastBody)
    #expect(try JSONDecoder().decode(Probe.self, from: sent) == Probe(limit: 7))
}

@Test func postDecodesTheResponse() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (200, Data(#"{"id":"abc123"}"#.utf8)) }

    let reply: Reply = try await makeClient().post("/x", body: Probe(limit: 1))
    #expect(reply == Reply(id: "abc123"))
}

@Test func httpErrorCarriesStatusAndServerMessage() async throws {
    StubURLProtocol.reset()
    let error = #"{"$_type":"Error","statusCode":400,"errorMessage":"Assignee must be an agent"}"#
    StubURLProtocol.responder = { _ in (400, Data(error.utf8)) }

    await #expect(throws: UnbluError.http(status: 400, message: "Assignee must be an agent")) {
        let _: Reply = try await makeClient().post("/conversations/create", body: Probe(limit: 1))
    }
}

@Test func nonJSONErrorBodyStillSurfacesStatus() async throws {
    StubURLProtocol.reset()
    StubURLProtocol.responder = { _ in (503, Data("upstream down".utf8)) }

    await #expect(throws: UnbluError.http(status: 503, message: "upstream down")) {
        let _: Reply = try await makeClient().post("/x", body: Probe(limit: 1))
    }
}
