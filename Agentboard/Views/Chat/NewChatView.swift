import SwiftUI

struct NewChatView: View {
    @Environment(BoardStore.self) private var store
    @Binding var selection: Destination?
    @State private var draft = ""
    @State private var recipient: String?
    @State private var attachment: BoardTask?
    @State private var sending = false
    @State private var error: String?

    private let starters = [
        "Compare flights from SFO to New York for Thanksgiving",
        "Find three good restaurants near me for Friday night",
        "Summarise what's on my calendar this week",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should your agents do?")
                        .font(.title2.bold())
                    Text("Send it and get on with your day. You'll see when an agent picks it up, and its reply lands here.")
                        .foregroundStyle(.secondary)
                }

                if !store.agents.isEmpty {
                    VStack(spacing: 8) {
                        AgentChoice(name: nil, detail: "Whoever picks it up first", selected: recipient == nil) { recipient = nil }
                        ForEach(store.agents) { agent in
                            AgentChoice(name: agent.name, detail: Presence.summary(agent), selected: recipient == agent.name,
                                        dimmed: Presence.isAsleep(agent)) { recipient = agent.name }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Try").font(.headline)
                    ForEach(starters, id: \.self) { starter in
                        Button { draft = starter } label: {
                            Text(starter)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("New chat")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Composer(agents: store.agents, recipient: $recipient, draft: $draft, attachment: $attachment, sending: sending) {
                Task { await send() }
            }
        }
        .alert("Couldn't send", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let id = try await store.startThread(body: text, to: recipient)
            draft = ""
            selection = .thread(id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct AgentChoice: View {
    let name: String?
    let detail: String
    let selected: Bool
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AgentAvatar(name: name, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AgentStyle.displayName(name)).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(dimmed ? .orange : .secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 1.5 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
