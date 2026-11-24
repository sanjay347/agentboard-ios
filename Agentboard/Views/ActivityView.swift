import SwiftUI

/// Everything the owner and the agents changed on the board, newest first.
struct ActivityView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        List(store.board?.events ?? []) { event in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(event.action))
                    .foregroundStyle(event.actor == "owner" ? Color.secondary : Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.summary)
                    Text("\(event.actor) · \(event.createdAt, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if store.board?.events.isEmpty == true {
                ContentUnavailableView("No activity yet", systemImage: "clock")
            }
        }
        .navigationTitle("Activity")
        .refreshable { await store.refresh() }
    }

    private func symbol(_ action: String) -> String {
        switch action {
        case "task_posted": "plus.circle"
        case "task_claimed": "hand.raised"
        case "task_done": "checkmark.circle"
        case "task_updated": "pencil.circle"
        case "memory_saved": "brain"
        case "agent_added": "person.badge.plus"
        case "agent_revoked": "person.badge.minus"
        default: "circle"
        }
    }
}
