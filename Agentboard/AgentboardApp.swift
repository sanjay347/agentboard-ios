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

struct MainView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        TabView {
            Tab("Board", systemImage: "square.grid.2x2") { BoardView() }
            Tab("Memory", systemImage: "brain") { MemoryView() }
            Tab("Agents", systemImage: "person.2") { AgentsView() }
        }
        // One poll loop for the whole app, alive while the main view is.
        .task { await store.keepFresh() }
    }
}
