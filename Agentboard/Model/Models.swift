import Foundation

// Mirrors the JSON the Agentboard server returns. Field names arrive in
// snake_case and are converted by the decoder, so they read naturally here.

enum TaskStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case open
    case inProgress = "in_progress"
    case blocked
    case done
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: "Open"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }

    var symbol: String {
        switch self {
        case .open: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.circle"
        case .done: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}

/// Named BoardTask, not Task, so it never shadows Swift Concurrency's Task.
struct BoardTask: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let details: String
    let status: TaskStatus
    let createdBy: String
    let assignedTo: String?
    let claimedBy: String?
    let dependsOn: String?
    let result: String?
    let note: String?
    // Optional so the app still reads boards running an older server.
    let threadId: String?
    let openedAt: Date?
    let claimedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    /// The agent this task is with: whoever claimed it, else whoever it was sent to.
    var agent: String? { claimedBy ?? assignedTo }

    /// Who the task is with, in the same words the web dashboard uses.
    var holder: String {
        if status == .cancelled { return "cancelled" }
        if status == .done, let claimedBy { return "done by \(claimedBy)" }
        if let claimedBy { return "\(claimedBy) is on it" }
        if let assignedTo { return "for \(assignedTo)" }
        return "anyone"
    }
}

struct Agent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    /// When the agent last called any tool on the board.
    let lastSeen: Date?
    /// Median seconds from a task becoming available to this agent claiming it.
    let typicalPickupSeconds: Int?
    let pickups: Int?
}

struct Memory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let content: String
    let tags: String
    let createdBy: String
    let createdAt: Date
}

struct BoardEvent: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let actor: String
    let action: String
    let subject: String
    let summary: String
    let createdAt: Date
}

struct Workspace: Codable, Hashable, Sendable {
    let id: String
    let name: String
}

struct Board: Codable, Sendable {
    let workspace: Workspace
    let agents: [Agent]
    let tasks: [BoardTask]
    let memories: [Memory]
    let events: [BoardEvent]

    func tasks(_ status: TaskStatus) -> [BoardTask] { tasks.filter { $0.status == status } }
    func task(_ id: String) -> BoardTask? { tasks.first { $0.id == id } }
}

/// Returned once when an agent is added. The token is never shown again:
/// the server keeps only its hash.
struct NewAgent: Codable, Sendable, Identifiable {
    struct Summary: Codable, Sendable { let id: String; let name: String }
    let agent: Summary
    let token: String
    let mcpUrl: String
    let mcpUrlWithToken: String
    var id: String { agent.id }
}

struct TaskDraft: Sendable {
    var title = ""
    var details = ""
    var assignedTo: String?
    var dependsOn: String?
}
