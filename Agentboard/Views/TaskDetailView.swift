import SwiftUI

struct TaskDetailView: View {
    @Environment(BoardStore.self) private var store
    let taskID: String

    var body: some View {
        // Looked up on every refresh, so a claim or completion appears live.
        if let board = store.board, let task = board.task(taskID) {
            List {
                Section {
                    Text(task.title).font(.title3.bold())
                    Label(task.status.label, systemImage: task.status.symbol)
                    LabeledContent("With", value: task.holder)
                    LabeledContent("Posted by", value: task.createdBy)
                    LabeledContent("Posted") { Text(task.createdAt, format: .dateTime.day().month().hour().minute()) }
                    LabeledContent("Last change") { Text(task.updatedAt, format: .relative(presentation: .named)) }
                }

                if !task.details.isEmpty {
                    Section("Details") { Text(task.details).textSelection(.enabled) }
                }

                if let dependsOn = task.dependsOn {
                    Section("Waits on") {
                        if let dep = board.task(dependsOn) {
                            NavigationLink(value: dep.id) {
                                Label(dep.title, systemImage: dep.status.symbol)
                            }
                        } else {
                            Text(dependsOn).font(.footnote.monospaced())
                        }
                    }
                }

                if let note = task.note, !note.isEmpty {
                    Section("Latest note") { Text(note).textSelection(.enabled) }
                }

                if let result = task.result, !result.isEmpty {
                    Section("Result") {
                        Text(result).textSelection(.enabled)
                        ShareLink(item: result) { Label("Share result", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle(task.status.label)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Task not found", systemImage: "questionmark.square.dashed")
        }
    }
}
