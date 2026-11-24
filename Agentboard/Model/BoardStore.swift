import Foundation
import Observation

/// The app's single source of truth: the connection and the latest board.
/// Every change goes to the server first and then re-reads the board, so the
/// phone never shows a state the server doesn't have.
@MainActor
@Observable
final class BoardStore {
    private(set) var connection: Connection?
    private(set) var board: Board?
    private(set) var threads: [ThreadSummary] = []
    private(set) var threadDetails: [String: ThreadDetail] = [:]
    private(set) var threadErrors: [String: String] = [:]
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?
    var memoryQuery = ""

    init(connection: Connection? = ConnectionStore.load()) {
        self.connection = connection
    }

    private var client: BoardClient? { connection.map { BoardClient(connection: $0) } }

    // MARK: Connecting

    /// Checks the key against the server before saving anything.
    func connect(server: String, key: String) async throws {
        guard let candidate = Connection.parse(server: server, key: key) else {
            throw BoardError.rejected("Enter the board's address and its owner key.")
        }
        let board = try await BoardClient(connection: candidate).board()
        try ConnectionStore.save(candidate)
        connection = candidate
        self.board = board
        lastError = nil
        lastRefresh = .now
    }

    func disconnect() {
        ConnectionStore.clear()
        connection = nil
        board = nil
        focusedThreadID = nil
        threads = []
        threadDetails = [:]
        lastError = nil
    }

    // MARK: Reading

    var agents: [Agent] { board?.agents ?? [] }
    func agent(named name: String?) -> Agent? { agents.first { $0.name == name } }

    func refresh() async {
        guard let client else { return }
        do {
            async let board = client.board(memoryQuery: memoryQuery)
            async let threads = client.threads()
            (self.board, self.threads) = try await (board, threads)
            lastError = nil
            lastRefresh = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Conversations

    /// Re-reads one conversation. Anything unread is marked read, because
    /// the person is looking at it right now.
    func refreshThread(_ id: String) async {
        guard let client else { return }
        do {
            var detail = try await client.thread(id)
            if detail.unread {
                try await client.markRead(threadID: id)
                detail = try await client.thread(id)
                threads = try await client.threads()
            }
            threadDetails[id] = detail
            threadErrors[id] = nil
        } catch {
            threadErrors[id] = error.localizedDescription
        }
    }

    /// Starts a conversation and returns its id.
    func startThread(body: String, to agent: String?) async throws -> String {
        guard let client else { throw BoardError.unauthorized }
        let started = try await client.startThread(body: body, to: agent)
        await afterChange(in: started.thread.id)
        return started.thread.id
    }

    func send(threadID: String, body: String, to agent: String?, dependsOn: String?) async throws {
        _ = try await client?.sendMessage(threadID: threadID, body: body, to: agent, dependsOn: dependsOn)
        await afterChange(in: threadID)
    }

    func reply(to task: BoardTask, body: String) async throws {
        _ = try await client?.reply(taskID: task.id, body: body)
        await afterChange(in: task.threadId)
    }

    func reassign(_ task: BoardTask, to agent: String?) async throws {
        _ = try await client?.reassign(taskID: task.id, to: agent)
        await afterChange(in: task.threadId)
    }

    func cancel(_ task: BoardTask) async throws {
        _ = try await client?.cancel(taskID: task.id)
        await afterChange(in: task.threadId)
    }

    private func afterChange(in threadID: String?) async {
        if let threadID { await refreshThread(threadID) }
        await refresh()
    }

    /// The conversation on screen, if any. Set from navigation, not from the
    /// thread view's lifecycle: a per-view task was cancelled whenever the chat
    /// list re-sorted, and the open conversation silently stopped updating.
    private(set) var focusedThreadID: String?

    func focus(threadID: String?) {
        focusedThreadID = threadID
        if let threadID { Task { await refreshThread(threadID) } }
    }

    /// The app's one refresh loop: the open conversation every 3 seconds, the
    /// board and the chat list every 6, so an agent's reply shows up without
    /// pulling to refresh.
    func keepFresh() async {
        var tick = 0
        while !Task.isCancelled {
            if let id = focusedThreadID { await refreshThread(id) }
            if tick % 2 == 0 { await refresh() }
            tick += 1
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: Writing

    func postTask(_ draft: TaskDraft) async throws {
        guard let client else { return }
        _ = try await client.postTask(draft)
        await refresh()
    }

    func addAgent(name: String) async throws -> NewAgent {
        guard let client else { throw BoardError.unauthorized }
        let created = try await client.addAgent(name: name)
        await refresh()
        return created
    }

    func revokeAgent(_ agent: Agent) async throws {
        try await client?.revokeAgent(id: agent.id)
        await refresh()
    }

    func remember(_ content: String) async throws {
        _ = try await client?.remember(content)
        await refresh()
    }

    func forget(_ memory: Memory) async throws {
        try await client?.forget(memoryID: memory.id)
        await refresh()
    }
}
