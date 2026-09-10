import Foundation

enum UnbluError: Error, Equatable {
    case http(status: Int, message: String)
    case transport(String)
    case decoding(String)
}

/// Thin HTTP layer over the Unblu Web API v4.
struct UnbluClient: Sendable {
    private let baseURL: URL
    private let authorization: String
    private let session: URLSession

    init(baseURL: URL, username: String, password: String, session: URLSession = .shared) {
        self.baseURL = Self.normalised(baseURL)
        self.authorization = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
        self.session = session
    }

    func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        let data = try await send(path, body: body)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UnbluError.decoding("\(error)")
        }
    }

    /// Completes a server address into the v4 API root.
    ///
    /// A host on its own, or one ending in /app, produces a 404 on every call
    /// with nothing in the body to say why.
    nonisolated static func normalised(_ baseURL: URL) -> URL {
        var path = baseURL.path
        while path.hasSuffix("/") { path.removeLast() }
        guard !path.contains("/rest/v") else {
            return URL(string: baseURL.absoluteString.hasSuffix("/")
                       ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString) ?? baseURL
        }

        let suffix = path.hasSuffix("/app") ? "/rest/v4" : "/app/rest/v4"
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path + suffix
        return components?.url ?? baseURL
    }

    /// Download links are rooted at the server, not under /app/rest/v4, so
    /// the origin has to be recovered from the configured base URL.
    static func origin(of baseURL: URL) -> URL {
        var url = baseURL
        while !url.path.isEmpty, url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        return url
    }

    /// Resolves a download link.
    ///
    /// Servers return these either server-rooted or absolute, and prefixing the
    /// origin onto an absolute one produced https://host/https://host/... —
    /// which fails, silently, leaving chat images blank.
    nonisolated static func downloadURL(for link: String, base: URL) -> URL? {
        if let absolute = URL(string: link), absolute.scheme != nil { return absolute }
        return origin(of: base).appendingPathComponent(link)
    }

    /// Fetches raw bytes from a download link.
    func data(atServerPath path: String) async throws -> (Data, String?) {
        guard let url = Self.downloadURL(for: path, base: baseURL) else {
            throw UnbluError.transport("Could not resolve the download link: \(path)")
        }
        var request = URLRequest(url: url)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UnbluError.transport(Self.describe(error, url: url))
        }
        guard let http = response as? HTTPURLResponse else {
            throw UnbluError.transport("non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw UnbluError.http(status: http.statusCode,
                                  message: Self.failure(status: http.statusCode,
                                                        body: data,
                                                        url: request.url))
        }
        return (data, http.value(forHTTPHeaderField: "Content-Type"))
    }

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UnbluError.transport(Self.describe(error, url: request.url))
        }
        guard let http = response as? HTTPURLResponse else {
            throw UnbluError.transport("non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw UnbluError.http(status: http.statusCode,
                                  message: Self.failure(status: http.statusCode,
                                                        body: data,
                                                        url: request.url))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UnbluError.decoding("\(error)")
        }
    }

    func postIgnoringResponse<Request: Encodable>(_ path: String, body: Request) async throws {
        _ = try await send(path, body: body)
    }

    private func send<Request: Encodable>(_ path: String, body: Request) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UnbluError.transport(Self.describe(error, url: request.url))
        }

        guard let http = response as? HTTPURLResponse else {
            throw UnbluError.transport("non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw UnbluError.http(status: http.statusCode,
                                  message: Self.failure(status: http.statusCode,
                                                        body: data,
                                                        url: request.url))
        }
        return data
    }

    /// A 404 from the wrong address has an empty body, so the address is the
    /// only useful thing to report.
    private static func failure(status: Int, body: Data, url: URL?) -> String {
        let message = errorMessage(from: body)
        guard message.isEmpty else { return message }
        let address = url?.absoluteString ?? "the server"
        guard status == 404 else { return "No response body from \(address)" }
        return "Not found: \(address)\n\n"
            + "The server address should be the Unblu host — UnbluMeet adds "
            + "/app/rest/v4 itself."
    }

    /// macOS reports a blocked Local Network request as "the Internet
    /// connection appears to be offline", which sends people looking at their
    /// wifi.
    private static func describe(_ error: Error, url: URL?) -> String {
        let text = "\(error)"
        let blocked = text.contains("Local network prohibited")
            || (text.contains("-1009") && (url?.host.map(isPrivateHost) ?? false))
        guard blocked else { return text }
        return "Local Network access is blocked for UnbluMeet.\n\n"
            + "Open System Settings > Privacy & Security > Local Network and "
            + "enable UnbluMeet, then try again. macOS reports this as \"the "
            + "Internet connection appears to be offline\", which is misleading."
            + "\n\n" + text
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        host == "localhost"
            || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
            || host.hasPrefix("127.")
            || host.hasSuffix(".local")
    }

    /// Unblu returns `{"$_type":"Error", "errorMessage":"..."}`.
    private static func errorMessage(from data: Data) -> String {
        struct ErrorBody: Decodable { let errorMessage: String? }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
           let message = body.errorMessage {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "unknown error"
    }
}
