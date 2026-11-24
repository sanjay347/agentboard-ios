import SwiftUI
import UIKit

/// One conversation. Your messages are bubbles; an agent's output is a card,
/// because it is work product you'll copy, share or hand on. The timeline
/// shows real board events only (sent, picked up, notes, replies), never a
/// fake typing indicator.
struct ThreadView: View {
    @Environment(BoardStore.self) private var store
    let threadID: String

    @State private var draft = ""
    /// nil until the user picks; until then the last agent in the thread is used.
    @State private var chosenRecipient: String??
    @State private var attachment: BoardTask?
    @State private var dismissedQuestion: String?
    @State private var sending = false
    @State private var error: String?
    @State private var toast: String?

    private var detail: ThreadDetail? { store.threadDetails[threadID] }

    var body: some View {
        Group {
            if let detail {
                conversation(detail)
            } else if let message = store.threadErrors[threadID] {
                ContentUnavailableView {
                    Label("Can't load this chat", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await store.refreshThread(threadID) } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(detail?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: toast)
        .alert("Something went wrong", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Layout

    private func conversation(_ detail: ThreadDetail) -> some View {
        let recipient = Binding<String?>(
            get: { chosenRecipient ?? detail.lastAgent },
            set: { chosenRecipient = .some($0) }
        )
        let question = detail.blockedTask.flatMap { $0.id == dismissedQuestion ? nil : $0 }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let stale = store.threadErrors[threadID] {
                    Label("Not up to date: \(stale)", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                ForEach(detail.messages) { message in
                    MessageView(
                        message: message,
                        task: detail.task(message.taskId),
                        agents: store.agents,
                        onHandOff: { agent, task in
                            chosenRecipient = .some(agent)
                            attachment = task
                            dismissedQuestion = detail.blockedTask?.id
                        },
                        onCopy: { text in
                            UIPasteboard.general.string = text
                            show("Copied")
                        }
                    )
                }
                ForEach(detail.tasks.filter { $0.status == .open || $0.status == .inProgress }) { task in
                    ActiveTaskView(task: task, agent: store.agent(named: task.agent), agents: store.agents,
                                   onNudge: { nudge(task) },
                                   onReassign: { agent in perform { try await store.reassign(task, to: agent) } },
                                   onCancel: { perform { try await store.cancel(task) } })
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Composer(
                agents: store.agents,
                recipient: recipient,
                draft: $draft,
                answering: question,
                onStopAnswering: { dismissedQuestion = question?.id },
                attachment: $attachment,
                sending: sending
            ) {
                Task { await send(answering: question, to: recipient.wrappedValue) }
            }
        }
    }

    // MARK: - Actions

    private func send(answering question: BoardTask?, to recipient: String?) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            if let question {
                try await store.reply(to: question, body: text)
            } else {
                try await store.send(threadID: threadID, body: text, to: recipient, dependsOn: attachment?.id)
            }
            draft = ""
            attachment = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The app can't wake an agent, and doesn't pretend to: it copies a
    /// prompt for you to paste into the agent's own app.
    private func nudge(_ task: BoardTask) {
        UIPasteboard.general.string = "Please check Agentboard: there's a task waiting for you."
        show("Copied. Paste it into \(AgentStyle.displayName(task.agent)) to nudge it.")
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }
}

// MARK: - Messages

private struct MessageView: View {
    @Environment(\.agentColors) private var colors
    let message: ThreadMessage
    let task: BoardTask?
    let agents: [Agent]
    let onHandOff: (String, BoardTask) -> Void
    let onCopy: (String) -> Void

    var body: some View {
        switch message.kind {
        case .request where message.fromOwner:
            UserBubble(text: message.body, caption: requestCaption)
        case .request:
            SystemLine(text: "\(AgentStyle.displayName(message.author)) asked \(task?.assignedTo.map(AgentStyle.displayName) ?? "any agent"): \(message.body.firstLine)")
        case .reply:
            UserBubble(text: message.body, caption: "Answer to \(AgentStyle.displayName(task?.agent))")
        case .claimed:
            Receipt(text: "\(AgentStyle.displayName(message.author)) picked it up", date: message.createdAt)
        case .note:
            HStack(alignment: .top, spacing: 8) {
                AgentAvatar(name: message.author, size: 20)
                Text(message.body).font(.subheadline).foregroundStyle(.secondary)
            }
        case .question:
            AgentCard(author: message.author, label: "is asking", tint: .orange, date: message.createdAt) {
                MarkdownText(message.body)
            }
        case .result:
            AgentCard(author: message.author, label: nil, tint: AgentTint(colors: colors)(message.author), date: message.createdAt) {
                MarkdownText(message.body)
                if let task { ResultActions(task: task, result: message.body, author: message.author, agents: agents, onHandOff: onHandOff, onCopy: onCopy) }
            }
        case .system:
            SystemLine(text: message.body)
        }
    }

    private var requestCaption: String? {
        guard let task else { return nil }
        var parts = ["to \(AgentStyle.displayName(task.assignedTo))"]
        if task.dependsOn != nil { parts.append("with the earlier result attached") }
        return parts.joined(separator: " · ")
    }
}

private struct UserBubble: View {
    let text: String
    let caption: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .foregroundStyle(.white)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }
}

private struct AgentCard<Content: View>: View {
    let author: String
    let label: String?
    let tint: Color
    let date: Date
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentAvatar(name: author, size: 24)
                Text(AgentStyle.displayName(author)).font(.subheadline.weight(.semibold))
                if let label { Text(label).font(.subheadline).foregroundStyle(tint) }
                Spacer()
                Text(date, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .padding(.trailing, 24)
    }
}

private struct ResultActions: View {
    let task: BoardTask
    let result: String
    let author: String
    let agents: [Agent]
    let onHandOff: (String, BoardTask) -> Void
    let onCopy: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { onCopy(result) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Menu {
                ForEach(agents.filter { $0.name != author }) { agent in
                    Button(AgentStyle.displayName(agent.name)) { onHandOff(agent.name, task) }
                }
            } label: {
                Label("Hand to", systemImage: "arrow.left.arrow.right")
            }
            .disabled(agents.filter { $0.name != author }.isEmpty)
            Button { onHandOff(author, task) } label: { Label("Follow up", systemImage: "arrowshape.turn.up.right") }
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }
}

private struct Receipt: View {
    let text: String
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hand.raised.fill")
            Text(text)
            Text("·")
            Text(date, format: .dateTime.hour().minute())
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct SystemLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// Agents reply in plain text that often uses Markdown. Render it, keeping line breaks.
private struct MarkdownText: View {
    let source: String
    init(_ source: String) { self.source = source }

    var body: some View {
        Text(rendered).textSelection(.enabled)
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
    }
}

// MARK: - Work in flight

/// The live line at the bottom for anything not finished: waiting to be picked
/// up, or being worked on. When an agent stays quiet too long, the user gets
/// options instead of a spinner.
private struct ActiveTaskView: View {
    let task: BoardTask
    let agent: Agent?
    let agents: [Agent]
    let onNudge: () -> Void
    let onReassign: (String?) -> Void
    let onCancel: () -> Void
    @State private var confirmCancel = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .confirmationDialog("Cancel this request?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel request", role: .destructive, action: onCancel)
        } message: {
            Text("\(AgentStyle.displayName(task.agent)) won't be able to pick it up.")
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let opened = task.openedAt ?? task.createdAt
        let who = AgentStyle.displayName(task.agent)
        if task.status == .inProgress {
            HStack(spacing: 8) {
                AgentAvatar(name: task.agent, size: 20)
                Text("\(who) is working on it · \(Presence.short(since: task.claimedAt ?? task.updatedAt, now: now))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative, options: .repeating).foregroundStyle(.secondary)
            }
        } else {
            let overdue = Presence.isOverdue(since: opened, typical: agent?.typicalPickupSeconds, now: now)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if overdue {
                        Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(overdue
                             ? "\(task.agent == nil ? "No agent has" : "\(who) hasn't") picked this up in \(Presence.short(since: opened, now: now))"
                             : (task.agent == nil ? "Waiting for any agent to pick this up" : "Waiting for \(who) to pick this up"))
                            .font(.subheadline.weight(overdue ? .medium : .regular))
                        if !overdue, let expected = Presence.pickup(agent?.typicalPickupSeconds) {
                            Text(expected.prefix(1).uppercased() + expected.dropFirst()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    if overdue, task.agent != nil {
                        Button("Nudge", systemImage: "hand.tap", action: onNudge)
                    }
                    Menu {
                        Button("Any agent") { onReassign(nil) }
                        ForEach(agents.filter { $0.name != task.agent }) { other in
                            Button {
                                onReassign(other.name)
                            } label: {
                                Text(AgentStyle.displayName(other.name))
                                Text(Presence.summary(other))
                            }
                        }
                    } label: {
                        Label("Reassign", systemImage: "arrow.triangle.swap")
                    }
                    Button("Cancel", systemImage: "xmark", role: .destructive) { confirmCancel = true }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((overdue ? Color.orange : Color.secondary).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
