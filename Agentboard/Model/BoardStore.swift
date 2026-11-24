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
        lastError = nil
    }

    // MARK: Reading

    func refresh() async {
        guard let client else { return }
        do {
            board = try await client.board(memoryQuery: memoryQuery)
            lastError = nil
            lastRefresh = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-reads the board every few seconds while a view keeps it alive, so an
    /// agent claiming a task shows up without a pull to refresh.
    func keepFresh(every seconds: Double = 5) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(seconds))
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
