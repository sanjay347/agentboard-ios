import Foundation

/// Where the board is and the key that owns it.
struct Connection: Codable, Sendable, Equatable {
    var serverURL: URL
    var ownerKey: String

    /// Accepts what people actually paste: missing scheme, trailing slash, spaces.
    static func parse(server: String, key: String) -> Connection? {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") {
            // A board running on this machine serves plain http; everything else should be https.
            let local = ["localhost", "127.0.0.1", "[::1]"].contains { text.hasPrefix($0) }
            text = (local ? "http://" : "https://") + text
        }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.host() != nil, !key.isEmpty else { return nil }
        return Connection(serverURL: url, ownerKey: key)
    }
}

enum BoardError: LocalizedError, Equatable {
    case unauthorized
    case rejected(String)
    case unreachable(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unauthorized: "The board didn't accept that owner key."
        case .rejected(let message): message
        case .unreachable(let detail): "Can't reach the board. \(detail)"
        case .unreadable: "The board sent a response this app doesn't understand."
        }
    }
}

/// The owner REST API (`/api/...`) of an Agentboard server. Agents use the MCP
/// endpoint; this app is the person's side of the same board.
struct BoardClient: Sendable {
    let connection: Connection
    var session: URLSession = .shared

    func board(memoryQuery: String = "") async throws -> Board {
        let query = memoryQuery.isEmpty ? [] : [URLQueryItem(name: "q", value: memoryQuery)]
        return try await send("GET", "api/board", query: query)
    }

    func postTask(_ draft: TaskDraft) async throws -> BoardTask {
        var body = ["title": draft.title]
        if !draft.details.isEmpty { body["details"] = draft.details }
        if let assignedTo = draft.assignedTo { body["assigned_to"] = assignedTo }
        if let dependsOn = draft.dependsOn { body["depends_on"] = dependsOn }
        return try await send("POST", "api/tasks", body: body)
    }

    func addAgent(name: String) async throws -> NewAgent {
        try await send("POST", "api/agents", body: ["name": name])
    }

    func revokeAgent(id: String) async throws {
        try await sendExpectingNoContent("DELETE", "api/agents/\(id)")
    }

    func remember(_ content: String) async throws -> Memory {
        try await send("POST", "api/memories", body: ["content": content])
    }

    func forget(memoryID: String) async throws {
        try await sendExpectingNoContent("DELETE", "api/memories/\(memoryID)")
    }

    /// One row read on the server: changes whenever anything visible on the board changes.
    func version() async throws -> Int {
        struct Version: Decodable { let version: Int }
        let v: Version = try await send("GET", "api/version")
        return v.version
    }

    // MARK: Conversations

    func agents() async throws -> [Agent] {
        try await send("GET", "api/agents")
    }

    func threads() async throws -> [ThreadSummary] {
        try await send("GET", "api/threads")
    }

    func thread(_ id: String) async throws -> ThreadDetail {
        try await send("GET", "api/threads/\(id)")
    }

    /// `to: nil` leaves the request open to whichever agent picks it up first.
    func startThread(body: String, to agent: String?) async throws -> StartedThread {
        var payload = ["body": body]
        if let agent { payload["to"] = agent }
        return try await send("POST", "api/threads", body: payload)
    }

    /// `dependsOn` hands an earlier task's result to this request: the hand-off.
    func sendMessage(threadID: String, body: String, to agent: String?, dependsOn: String?) async throws -> BoardTask {
        var payload = ["body": body]
        if let agent { payload["to"] = agent }
        if let dependsOn { payload["depends_on"] = dependsOn }
        return try await send("POST", "api/threads/\(threadID)/messages", body: payload)
    }

    func markRead(threadID: String) async throws {
        try await sendExpectingNoContent("POST", "api/threads/\(threadID)/read")
    }

    func reply(taskID: String, body: String) async throws -> BoardTask {
        try await send("POST", "api/tasks/\(taskID)/reply", body: ["body": body])
    }

    func reassign(taskID: String, to agent: String?) async throws -> BoardTask {
        try await send("POST", "api/tasks/\(taskID)/reassign", body: agent.map { ["to": $0] } ?? [:])
    }

    func cancel(taskID: String) async throws -> BoardTask {
        try await send("POST", "api/tasks/\(taskID)/cancel", body: [:])
    }

    // MARK: - Transport

    private func send<T: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: [String: String]? = nil
    ) async throws -> T {
        let data = try await perform(method, path, query: query, body: body)
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw BoardError.unreadable
        }
    }

    private func sendExpectingNoContent(_ method: String, _ path: String) async throws {
        _ = try await perform(method, path, query: [], body: nil)
    }

    private func perform(_ method: String, _ path: String, query: [URLQueryItem], body: [String: String]?) async throws -> Data {
        var components = URLComponents(url: connection.serverURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw BoardError.unreachable("The server address isn't valid.") }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(connection.ownerKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw BoardError.unreachable(Self.describe(error))
        }

        guard let http = response as? HTTPURLResponse else { throw BoardError.unreadable }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw BoardError.unauthorized
        default:
            // The server answers errors as {"error": "..."}; show its words.
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw BoardError.rejected(message ?? "The board returned HTTP \(http.statusCode).")
        }
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            "That address doesn't resolve. If it's a trycloudflare.com link, the tunnel may have restarted with a new address."
        case .notConnectedToInternet: "You're offline."
        case .timedOut: "The request timed out."
        case .cannotConnectToHost: "Nothing is answering at that address. Is the server running?"
        case .appTransportSecurityRequiresSecureConnection: "Use an https address. Plain http is only allowed for localhost."
        default: error.localizedDescription
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            // Server timestamps are ISO 8601 with milliseconds: 2026-11-24T03:38:21.000Z
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date \(text)"))
        }
        return decoder
    }
}
