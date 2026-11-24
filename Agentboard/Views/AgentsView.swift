import SwiftUI

struct AgentsView: View {
    @Environment(BoardStore.self) private var store
    @State private var naming = false
    @State private var newName = ""
    @State private var created: NewAgent?
    @State private var revoking: Agent?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.board?.agents ?? []) { agent in
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(agent.name).font(.headline)
                                Text("Connected \(agent.createdAt, format: .relative(presentation: .named))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Revoke", systemImage: "xmark.circle", role: .destructive) { revoking = agent }
                        }
                    }
                } footer: {
                    Text("Each agent has its own connector link. Revoking one cuts that agent off without touching the others.")
                }
            }
            .overlay {
                if store.board?.agents.isEmpty == true {
                    ContentUnavailableView("No agents connected", systemImage: "person.2.slash",
                                           description: Text("Add one, then paste its link into the agent's connector settings."))
                }
            }
            .navigationTitle("Agents")
            .toolbar {
                Button("Add agent", systemImage: "plus") { newName = ""; naming = true }
            }
            .alert("Add an agent", isPresented: $naming) {
                TextField("duet, muse, dots…", text: $newName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Add") { Task { await add() } }
            } message: {
                Text("Lowercase letters, digits, - or _.")
            }
            .confirmationDialog(
                "Revoke \(revoking?.name ?? "")?",
                isPresented: .constant(revoking != nil),
                titleVisibility: .visible,
                presenting: revoking
            ) { agent in
                Button("Revoke", role: .destructive) { Task { await revoke(agent) } }
                Button("Cancel", role: .cancel) { revoking = nil }
            } message: { agent in
                Text("\(agent.name)'s connector stops working immediately. You can add it again with a new link.")
            }
            .sheet(item: $created) { agent in AgentLinkView(agent: agent) }
            .alert("Something went wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func add() async {
        let name = newName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return }
        do { created = try await store.addAgent(name: name) } catch { self.error = error.localizedDescription }
    }

    private func revoke(_ agent: Agent) async {
        revoking = nil
        do { try await store.revokeAgent(agent) } catch { self.error = error.localizedDescription }
    }
}

/// Shown exactly once, right after an agent is added: the server stores only a
/// hash of the token, so this is the only time the full link exists anywhere.
struct AgentLinkView: View {
    @Environment(\.dismiss) private var dismiss
    let agent: NewAgent
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(agent.mcpUrlWithToken)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = agent.mcpUrlWithToken
                        copied = true
                    }
                } header: {
                    Text("\(agent.agent.name)'s connector link")
                } footer: {
                    Label("This link is a password and won't be shown again. Paste it into the agent now.", systemImage: "lock")
                }

                Section("Claude Duet") {
                    Text("Connector settings → Add custom connector → paste the link.")
                }
                Section("Meta Muse") {
                    Text("Say: \u{201C}create a custom connector, name Agent Board, link <the link>\u{201D}. When Muse asks for the credential, paste only the part after /mcp/.")
                }
            }
            .navigationTitle("Connect \(agent.agent.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .interactiveDismissDisabled(!copied)
    }
}
