import SwiftUI
import DLNAKit

/// サーバー一覧画面（アプリのルート）。
struct ServerListView: View {
    @State private var model = LibraryModel()
    @State private var ratings = RatingsModel()
    @State private var favorites = FavoritesModel.shared
    @State private var showingAdd = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @State private var updater = UpdateChecker.shared
    #endif

    private var settingsPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.servers.isEmpty && model.discovered.isEmpty
                    && DownloadManager.shared.downloadedItems().isEmpty
                    && favorites.folders.isEmpty {
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
                ToolbarItem(placement: settingsPlacement) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                }
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
            .navigationDestination(for: TopRoute.self) { route in
                switch route {
                case .downloads: DownloadsView()
                }
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                BrowseView(server: route.server, objectID: route.objectID, title: route.title)
            }
            .navigationDestination(for: PlayerRoute.self) { route in
                PlayerView(items: route.items, startIndex: route.index)
            }
            .sheet(isPresented: $showingAdd) {
                AddServerView(model: model)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task {
                CloudSync.shared.start()
                model.reload()
                // 起動時の自動探索は行わない（手動の自動探索ボタン／引き下げ更新で実行）。
                #if os(macOS)
                // 起動時にサイレントで更新チェック。新版があれば下の .alert で確認する。
                await updater.checkOnLaunch()
                #endif
            }
            // iCloud 同期で他デバイスの変更を取り込んだらキャッシュを再読込。
            .onReceive(NotificationCenter.default.publisher(for: .cloudSyncDidUpdate)) { _ in
                ratings.reload()
                BookmarksModel.shared.reload()
                ThumbnailsModel.shared.reload()
                TagsModel.shared.reload()
                favorites.reload()
                model.reload()
            }
            #if os(macOS)
            // 起動時チェックで新版が見つかったときの確認ダイアログ。
            .alert("新しいバージョンがあります", isPresented: Binding(
                get: { updater.launchPrompt != nil },
                set: { if !$0 { updater.dismissLaunchPrompt() } }
            ), presenting: updater.launchPrompt) { release in
                Button("今すぐ更新") {
                    updater.dismissLaunchPrompt()
                    Task { await updater.update(to: release) }
                }
                Button("後で", role: .cancel) { updater.dismissLaunchPrompt() }
            } message: { release in
                Text("バージョン \(release.tagName) が利用可能です（現在 \(updater.currentVersion)）。今すぐダウンロードして更新しますか？ 更新後は自動で再起動します。")
            }
            #endif
        }
        .environment(ratings)
        // 他アプリ等から戻った時（前面化）に PiP が起動中なら自動解除する。
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            if phase == .active { PlaybackModel.shared.stopPiP() }
            #endif
        }
    }

    private var serverList: some View {
        List {
            // 1. DLNA サーバー（登録済み）
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
            // 2. ネットワーク上で発見したサーバー
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
            // 3. お気に入り
            if !favorites.folders.isEmpty {
                Section("お気に入り") {
                    ForEach(favorites.folders) { folder in
                        NavigationLink(value: BrowseRoute(server: folder.server, objectID: folder.objectID, title: folder.title)) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(folder.title)
                                    Text(folder.server.friendlyName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                favorites.remove(id: folder.id)
                            } label: {
                                Label("お気に入り解除", systemImage: "star.slash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                favorites.remove(id: folder.id)
                            } label: {
                                Label("お気に入り解除", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }
            // 4. ダウンロード済み（末尾）
            let downloaded = DownloadManager.shared.downloadedItems()
            if !downloaded.isEmpty {
                Section {
                    NavigationLink(value: TopRoute.downloads) {
                        Label("ダウンロード済み（\(downloaded.count)）", systemImage: "arrow.down.circle.fill")
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
