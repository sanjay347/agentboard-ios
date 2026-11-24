import SwiftUI

struct NewTaskView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TaskDraft()
    @State private var posting = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing", text: $draft.title, axis: .vertical)
                        .focused($titleFocused)
                    TextField("Details, and what a good result looks like", text: $draft.details, axis: .vertical)
                        .lineLimit(4...10)
                } footer: {
                    Text("Write it so an agent can finish it without asking you anything.")
                }

                Section("Who") {
                    Picker("Assign to", selection: $draft.assignedTo) {
                        Text("Anyone").tag(String?.none)
                        ForEach(store.board?.agents ?? []) { agent in
                            Text(agent.name).tag(Optional(agent.name))
                        }
                    }
                    Picker("After", selection: $draft.dependsOn) {
                        Text("Nothing").tag(String?.none)
                        ForEach(unfinished) { task in
                            Text(task.title).lineLimit(1).tag(Optional(task.id))
                        }
                    }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if posting {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await post() } }
                            .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    /// A task can only wait on work that isn't finished yet.
    private var unfinished: [BoardTask] {
        (store.board?.tasks ?? []).filter { $0.status != .done }
    }

    private func post() async {
        posting = true
        defer { posting = false }
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await store.postTask(draft)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
