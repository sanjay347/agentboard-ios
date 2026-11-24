import SwiftUI

struct MemoryView: View {
    @Environment(BoardStore.self) private var store
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                if let memories = store.board?.memories {
                    if memories.isEmpty {
                        ContentUnavailableView(
                            store.memoryQuery.isEmpty ? "Nothing remembered yet" : "No matches",
                            systemImage: "brain",
                            description: Text(store.memoryQuery.isEmpty
                                ? "Facts your agents save with remember show up here, and every agent on the board can recall them."
                                : "Try fewer words.")
                        )
                    }
                    ForEach(memories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.content).textSelection(.enabled)
                            HStack(spacing: 4) {
                                Text(memory.createdBy)
                                Text("·")
                                Text(memory.createdAt, format: .relative(presentation: .named))
                                if !memory.tags.isEmpty { Text("· \(memory.tags)") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Forget", systemImage: "trash", role: .destructive) {
                                Task { await forget(memory) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Memory")
            .searchable(text: $store.memoryQuery, prompt: "Search what agents remember")
            .onSubmit(of: .search) { Task { await store.refresh() } }
            .onChange(of: store.memoryQuery) { _, query in
                if query.isEmpty { Task { await store.refresh() } }
            }
            .refreshable { await store.refresh() }
            .toolbar {
                Button("Add memory", systemImage: "plus") { adding = true }
            }
            .sheet(isPresented: $adding) { NewMemoryView() }
            .alert("Couldn't forget that", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func forget(_ memory: Memory) async {
        do { try await store.forget(memory) } catch { self.error = error.localizedDescription }
    }
}

struct NewMemoryView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A fact every agent should know", text: $content, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("For durable facts: a preference, a decision, a reference. Never passwords or card numbers.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Remember")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.remember(content.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
