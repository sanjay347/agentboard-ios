import SwiftUI

enum Destination: Hashable {
    case newChat
    case thread(String)
    case board, memory, agents, activity

    var threadID: String? {
        if case .thread(let id) = self { return id }
        return nil
    }
}

/// The sidebar. Sorted by what each conversation needs from you, not by date:
/// replies can take minutes or hours, so the question on opening the app is
/// "does anything need me?"
struct ChatListView: View {
    @Environment(BoardStore.self) private var store
    @Binding var selection: Destination?
    @State private var confirmDisconnect = false
    /// The section the open conversation was in when you opened it. It stays
    /// there until you come back: if its row moved while selected, the list
    /// would drop the selection and, on iPhone, close the chat under you.
    @State private var pinned: (id: String, state: ThreadState)?

    private func section(of thread: ThreadSummary) -> ThreadState {
        pinned?.id == thread.id ? pinned!.state : thread.state
    }

    var body: some View {
        List(selection: $selection) {
            if !store.agents.isEmpty {
                Section { PresenceStrip(agents: store.agents) }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if let error = store.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange) }
            }

            if store.threads.isEmpty, store.board != nil {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ask your agents anything").font(.headline)
                        Text("Pick an agent, send a request, and put your phone away. Replies land here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    Label("New chat", systemImage: "square.and.pencil").tag(Destination.newChat)
                }
            }

            ForEach(ThreadState.allCases, id: \.self) { state in
                let items = store.threads.filter { section(of: $0) == state }
                if !items.isEmpty {
                    Section(state.label) {
                        ForEach(items) { thread in
                            ThreadRow(thread: thread).tag(Destination.thread(thread.id))
                        }
                    }
                }
            }

            Section("Board") {
                Label("Tasks", systemImage: "square.grid.2x2").tag(Destination.board)
                Label("Memory", systemImage: "brain").tag(Destination.memory)
                Label("Agents", systemImage: "person.2").tag(Destination.agents)
                Label("Activity", systemImage: "clock").tag(Destination.activity)
            }
        }
        .navigationTitle("Agentboard")
        .animation(.default, value: store.threads.map { "\($0.id)\(section(of: $0).rawValue)" })
        .onChange(of: selection, initial: true) { _, new in
            if let id = new?.threadID, let thread = store.threads.first(where: { $0.id == id }) {
                if pinned?.id != id { pinned = (id, thread.state) }
            } else if new?.threadID == nil {
                pinned = nil
            }
        }
        .refreshable { await store.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New chat", systemImage: "square.and.pencil") { selection = .newChat }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Disconnect", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmDisconnect = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Disconnect from this board?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { store.disconnect() }
        } message: {
            Text("The owner key is removed from this phone. The board and your agents are not affected.")
        }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AgentAvatar(name: thread.primaryAgent, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.title)
                        .font(.body.weight(thread.unread ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Presence.short(since: thread.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if thread.state == .needsYou {
                        Circle().fill(.orange).frame(width: 7, height: 7)
                    } else if thread.state == .working {
                        Image(systemName: "ellipsis").font(.caption2).symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                    Text(thread.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(thread.state == .needsYou ? .primary : .secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// Who's around right now. Shown at the top so you know before you ask.
struct PresenceStrip: View {
    let agents: [Agent]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(agents) { agent in
                    HStack(spacing: 6) {
                        AgentAvatar(name: agent.name, size: 26)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Presence.isAsleep(agent) ? Color.secondary : Color.green)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                            }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(AgentStyle.displayName(agent.name)).font(.caption.weight(.semibold))
                            Text(agent.lastSeen.map { Presence.short(since: $0) } ?? "never")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(AgentStyle.displayName(agent.name)), \(Presence.seen(agent.lastSeen))")
                }
            }
        }
    }
}
