import SwiftUI

struct ConnectView: View {
    @Environment(BoardStore.self) private var store
    @State private var server = ""
    @State private var key = ""
    @State private var connecting = false
    @State private var error: String?
    @FocusState private var field: Field?

    private enum Field { case server, key }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        Text("Your agents' shared board")
                            .font(.title2.bold())
                        Text("Duet, Muse and your other agents connect to the board as a connector. This app is your side of it: post work, watch who picks it up, see what they remember.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    TextField("https://your-board.example.com", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { field = .key }
                    // Return connects: on a phone the keyboard covers the button.
                    SecureField("owner_…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .key)
                        .submitLabel(.go)
                        .onSubmit { Task { await connect() } }
                } header: {
                    Text("Board")
                } footer: {
                    Text("The owner key is in CONNECT.md next to the server. It's stored in this phone's Keychain and sent only to this board.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Text("Connect")
                            if connecting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(connecting || server.isEmpty || key.isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Agentboard")
        }
    }

    private func connect() async {
        guard !connecting, !server.isEmpty, !key.isEmpty else { return }
        field = nil
        error = nil
        connecting = true
        defer { connecting = false }
        do {
            try await store.connect(server: server, key: key)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
