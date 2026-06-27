import SwiftUI
import DLNAKit

/// サーバー一覧画面（アプリのルート）。
struct ServerListView: View {
    @State private var model = LibraryModel()
    @State private var ratings = RatingsModel()
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if model.servers.isEmpty && model.discovered.isEmpty {
                    ContentUnavailableView {
                        Label("サーバーがありません", systemImage: "server.rack")
                    } description: {
                        Text("右上の＋から DLNA サーバーの記述 URL を追加するか、再読み込みで自動探索してください。\n例: http://192.168.1.10:8200/rootDesc.xml")
                    } actions: {
                        Button("自動探索") { Task { await model.discover() } }
                    }
                } else {
                    serverList
                }
            }
            .navigationTitle("DLNA サーバー")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    if model.isDiscovering {
                        ProgressView()
                    } else {
                        Button {
                            Task { await model.discover() }
                        } label: {
                            Label("自動探索", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                BrowseView(server: route.server, objectID: route.objectID, title: route.title)
            }
            .navigationDestination(for: PlayerRoute.self) { route in
                PlayerView(item: route.item)
            }
            .sheet(isPresented: $showingAdd) {
                AddServerView(model: model)
            }
            .task {
                model.reload()
                await model.discover()
            }
        }
        .environment(ratings)
    }

    private var serverList: some View {
        List {
            if !model.servers.isEmpty {
                Section("登録済み") {
                    ForEach(model.servers) { state in
                        ServerRow(state: state)
                            .swipeActions {
                                Button(role: .destructive) {
                                    model.remove(state)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            // macOS は右クリック、iOS は長押しで削除できる。
                            .contextMenu {
                                Button(role: .destructive) {
                                    model.remove(state)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            model.remove(model.servers[index])
                        }
                    }
                }
            }
            if !model.discovered.isEmpty {
                Section("ネットワーク上で発見") {
                    ForEach(model.discovered) { server in
                        NavigationLink(value: BrowseRoute(server: server, objectID: "0", title: server.friendlyName)) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(server.friendlyName)
                                    Text(server.descriptionURL.host ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "wifi")
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            await model.resolveAll()
            await model.discover()
        }
    }
}

/// サーバー 1 行。解決状態に応じて表示を切り替える。
private struct ServerRow: View {
    let state: LibraryModel.ServerState

    var body: some View {
        if let server = state.server {
            NavigationLink(value: BrowseRoute(server: server, objectID: "0", title: server.friendlyName)) {
                Label {
                    VStack(alignment: .leading) {
                        Text(server.friendlyName)
                        Text(server.descriptionURL.host ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "server.rack")
                }
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.displayName)
                    if state.isLoading {
                        Text("接続中…").font(.caption).foregroundStyle(.secondary)
                    } else if let error = state.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            } icon: {
                if state.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// 記述 URL を入力してサーバーを追加するシート。
struct AddServerView: View {
    let model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("DLNA サーバーの記述 URL") {
                    TextField("http://192.168.1.10:8200/rootDesc.xml", text: $urlString)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    if let error = model.addError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    Text("NAS やメディアサーバーのデバイス記述（device description）XML の URL を入力します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("サーバーを追加")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        Task {
                            isAdding = true
                            await model.addManualServer(urlString: urlString)
                            isAdding = false
                            if model.addError == nil { dismiss() }
                        }
                    }
                    .disabled(urlString.isEmpty || isAdding)
                }
            }
        }
    }
}
