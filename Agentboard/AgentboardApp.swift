import SwiftUI

@main
struct AgentboardApp: App {
    @State private var store = BoardStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

struct RootView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        if store.connection == nil {
            ConnectView()
        } else {
            MainView()
        }
    }
}

/// Chats in a sidebar on iPad and Mac; on iPhone the same view collapses so
/// the chat list is the first screen, the way Apple's own apps work.
struct MainView: View {
    @Environment(BoardStore.self) private var store
    @State private var selection: Destination?

    var body: some View {
        NavigationSplitView {
            ChatListView(selection: $selection)
        } detail: {
            switch selection {
            case .newChat: NewChatView(selection: $selection)
            case .thread(let id): ThreadView(threadID: id).id(id)
            case .board: BoardView()
            case .memory: MemoryView()
            case .agents: AgentsView()
            case .activity: ActivityView()
            case nil:
                ContentUnavailableView("Pick a chat", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Or start a new one and send it to an agent."))
            }
        }
        .agentColors(store.agents)
        .onChange(of: selection, initial: true) { _, new in store.focus(threadID: new?.threadID) }
        // One poll loop for the whole app, alive while the main view is.
        .task { await store.keepFresh() }
    }
}
