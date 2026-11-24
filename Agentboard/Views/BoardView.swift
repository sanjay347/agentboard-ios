import SwiftUI

struct BoardView: View {
    @Environment(BoardStore.self) private var store
    @State private var composing = false
    @State private var confirmDisconnect = false

    var body: some View {
        NavigationStack {
            Group {
                if let board = store.board {
                    List {
                        if let error = store.lastError {
                            StaleBanner(message: error)
                        }
                        if board.tasks.isEmpty {
                            ContentUnavailableView(
                                "No tasks yet",
                                systemImage: "tray",
                                description: Text("Post one and assign it to an agent, or leave it open for whoever gets to it first.")
                            )
                        }
                        ForEach(TaskStatus.allCases) { status in
                            let tasks = board.tasks(status)
                            if !tasks.isEmpty {
                                Section {
                                    ForEach(tasks) { task in
                                        NavigationLink(value: task.id) { TaskRow(task: task) }
                                    }
                                } header: {
                                    Label("\(status.label) · \(tasks.count)", systemImage: status.symbol)
                                }
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { id in TaskDetailView(taskID: id) }
                    .refreshable { await store.refresh() }
                } else if let error = store.lastError {
                    ContentUnavailableView {
                        Label("Can't reach the board", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await store.refresh() } }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(store.board?.workspace.name ?? "Board")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        NavigationLink { ActivityView() } label: { Label("Activity", systemImage: "clock") }
                        Button("Disconnect", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            confirmDisconnect = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New task", systemImage: "plus") { composing = true }
                        .disabled(store.board == nil)
                }
            }
            .sheet(isPresented: $composing) { NewTaskView() }
            .confirmationDialog("Disconnect from this board?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { store.disconnect() }
            } message: {
                Text("The owner key is removed from this phone. The board and your agents are not affected.")
            }
        }
    }
}

struct TaskRow: View {
    let task: BoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(task.holder)
                Text("·")
                Text(task.updatedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Shown above the content when the last refresh failed, so stale data is
/// never mistaken for current data.
struct StaleBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
    }
}
