import SwiftUI

/// The message bar. The recipient belongs to each message, not to the chat,
/// which is what lets one conversation move between agents.
struct Composer: View {
    let agents: [Agent]
    @Binding var recipient: String?
    @Binding var draft: String
    /// Set when an agent asked something: sending answers it instead of making a new request.
    var answering: BoardTask?
    var onStopAnswering: (() -> Void)?
    @Binding var attachment: BoardTask?
    var sending: Bool
    var onSend: () -> Void
    @FocusState private var focused: Bool

    private var target: String? { answering?.agent ?? recipient }
    private var canSend: Bool { !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let answering {
                Chip(systemImage: "arrowshape.turn.up.left", text: "Answering \(AgentStyle.displayName(answering.agent))") {
                    onStopAnswering?()
                }
            } else if let attachment {
                Chip(systemImage: "paperclip", text: "\(AgentStyle.displayName(attachment.agent))'s result attached") {
                    self.attachment = nil
                }
            }
            if answering == nil, let warning {
                Label(warning, systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if answering == nil {
                    RecipientMenu(agents: agents, recipient: $recipient)
                }
                TextField(placeholder, text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.vertical, 7)
                Button(action: onSend) {
                    Group {
                        if sending { ProgressView() } else { Image(systemName: "arrow.up") }
                    }
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(canSend ? Color.accentColor : Color.secondary.opacity(0.25), in: Circle())
                    .foregroundStyle(.white)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var placeholder: String {
        if let answering { return "Answer \(AgentStyle.displayName(answering.agent))" }
        return recipient == nil ? "Ask any agent" : "Message \(AgentStyle.displayName(recipient))"
    }

    private var warning: String? {
        guard let agent = agents.first(where: { $0.name == target }), Presence.isAsleep(agent) else { return nil }
        return "\(AgentStyle.displayName(agent.name)): \(Presence.seen(agent.lastSeen).lowercased()), so a reply may take a while."
    }
}

struct RecipientMenu: View {
    let agents: [Agent]
    @Binding var recipient: String?

    var body: some View {
        Menu {
            Button {
                recipient = nil
            } label: {
                Text("Auto")
                Text("Whoever picks it up first")
            }
            ForEach(agents) { agent in
                Button {
                    recipient = agent.name
                } label: {
                    Text(AgentStyle.displayName(agent.name))
                    Text(Presence.summary(agent))
                }
            }
        } label: {
            HStack(spacing: 5) {
                AgentAvatar(name: recipient, size: 22)
                Text(AgentStyle.displayName(recipient))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: Capsule())
        }
        .accessibilityLabel("Send to \(AgentStyle.displayName(recipient))")
    }
}

private struct Chip: View {
    let systemImage: String
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: Capsule())
    }
}
