import Foundation

// A conversation in the app is a thread on the board. Each message the user
// sends is a task, and the agent's result is the reply.

enum ThreadState: String, Codable, Sendable, CaseIterable {
    case needsYou = "needs_you"
    case working
    case waiting
    case done

    // A newer server may add states; show them as finished rather than failing to load.
    init(from decoder: Decoder) throws {
        self = ThreadState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .done
    }

    var label: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .waiting: "Waiting"
        case .done: "Done"
        }
    }
}

enum MessageKind: String, Codable, Sendable {
    case request, claimed, note, question, result, reply, system

    init(from decoder: Decoder) throws {
        self = MessageKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .system
    }
}

struct ThreadMessage: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let threadId: String
    let taskId: String?
    let author: String
    let kind: MessageKind
    let body: String
    let createdAt: Date

    var fromOwner: Bool { author == "owner" }
}

struct ThreadSummary: Codable, Identifiable, Hashable, Sendable {
    struct LastMessage: Codable, Hashable, Sendable {
        let author: String
        let kind: MessageKind
        let body: String
        let createdAt: Date
    }

    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let lastReadAt: Date?
    let state: ThreadState
    let unread: Bool
    let agents: [String]
    let lastMessage: LastMessage?

    /// The agent to show beside this conversation: whoever is asking you
    /// something, else the agent it's with now.
    var primaryAgent: String? {
        if state == .needsYou, let author = lastMessage?.author, author != "owner" { return author }
        return agents.last
    }

    /// The one line under the title in the chat list: what the conversation needs from you.
    var subtitle: String {
        let who = AgentStyle.displayName(primaryAgent)
        switch state {
        case .needsYou:
            guard let last = lastMessage else { return "\(who) replied" }
            let author = AgentStyle.displayName(last.author)
            return last.kind == .question ? "\(author) asked: \(last.body.firstLine)" : "\(author) replied: \(last.body.firstLine)"
        case .working:
            return "\(who) is on it"
        case .waiting:
            return primaryAgent == nil ? "Waiting for any agent" : "Waiting for \(who)"
        case .done:
            guard let last = lastMessage else { return "Done" }
            return last.author == "owner" ? last.body.firstLine : "\(AgentStyle.displayName(last.author)): \(last.body.firstLine)"
        }
    }
}

struct ThreadDetail: Codable, Sendable {
    let id: String
    let title: String
    let state: ThreadState
    let unread: Bool
    let agents: [String]
    let messages: [ThreadMessage]
    let tasks: [BoardTask]

    func task(_ id: String?) -> BoardTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// The most recent request's agent, used as the default recipient for the next message.
    var lastAgent: String? {
        tasks.last(where: { $0.createdBy == "owner" })?.agent
    }

    /// A task waiting on the user's answer, newest first.
    var blockedTask: BoardTask? { tasks.last { $0.status == .blocked } }
}

struct StartedThread: Codable, Sendable {
    let thread: ThreadSummary
    let task: BoardTask
}

extension String {
    /// The first line as plain text, for one-line previews: Markdown such as
    /// **bold** is rendered away rather than shown as asterisks.
    var firstLine: String {
        let line = trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        guard let plain = try? AttributedString(markdown: line) else { return line }
        return String(plain.characters)
    }
}
