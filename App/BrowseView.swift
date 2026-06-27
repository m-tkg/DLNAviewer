import SwiftUI
import DLNAKit

/// フォルダ（コンテナ）の中身を一覧表示する画面。
struct BrowseView: View {
    let server: MediaServer
    let objectID: String
    let title: String

    @Environment(RatingsModel.self) private var ratings
    @AppStorage("browseGridMode") private var gridMode = false
    // 評価フィルタ（ファイルのみ対象。フォルダは常に表示）。
    @AppStorage("filterLike") private var filterLike = true
    @AppStorage("filterDislike") private var filterDislike = true
    @AppStorage("filterNone") private var filterNone = true

    @State private var objects: [DIDLObject] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var showingSettings = false

    private let client = ContentDirectoryClient()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中…")
            } else if let error {
                ContentUnavailableView {
                    Label("読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("再試行") { Task { await load(force: true) } }
                }
            } else if displayObjects.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: searchText)
                } else if isFiltering {
                    ContentUnavailableView {
                        Label("該当する項目がありません", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("評価フィルタを変更してください。")
                    }
                } else {
                    ContentUnavailableView("項目がありません", systemImage: "tray")
                }
            } else if gridMode {
                grid
            } else {
                list
            }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "検索（正規表現可）")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle(isOn: $filterLike) { Label("Like", systemImage: "hand.thumbsup") }
                    Toggle(isOn: $filterDislike) { Label("Dislike", systemImage: "hand.thumbsdown") }
                    Toggle(isOn: $filterNone) { Label("評価なし", systemImage: "minus") }
                } label: {
                    Label("フィルタ",
                          systemImage: isFiltering
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    gridMode.toggle()
                } label: {
                    Label(gridMode ? "リスト表示" : "アイコン表示",
                          systemImage: gridMode ? "list.bullet" : "square.grid.2x2")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .task { await load() }
    }

    /// 表示対象。コンテナ（フォルダ）は評価フィルタ対象外、動画アイテムは評価フィルタを適用。
    /// 検索文字列があれば名前で絞り込む（フォルダ・ファイル両方）。
    private var displayObjects: [DIDLObject] {
        objects.filter { object in
            switch object {
            case .container(let container):
                return matchesSearch(container.title)
            case .item(let item):
                return item.isVideo
                    && ratingAllowed(ratings.rating(for: item))
                    && matchesSearch(item.title)
            }
        }
    }

    private func ratingAllowed(_ rating: Rating) -> Bool {
        switch rating {
        case .like: return filterLike
        case .dislike: return filterDislike
        case .none: return filterNone
        }
    }

    /// 検索文字列にマッチするか。正規表現として解釈し、無効なら部分一致にフォールバック。
    private func matchesSearch(_ title: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if let regex = try? Regex(query).ignoresCase() {
            return title.contains(regex)
        }
        return title.localizedCaseInsensitiveContains(query)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// いずれかのフィルタが無効ならフィルタ中とみなす。
    private var isFiltering: Bool {
        !(filterLike && filterDislike && filterNone)
    }

    @AppStorage("thumbnailSize") private var thumbnailSize = 1

    /// リスト行のサムネイルサイズ（16:9・3段階）。
    private var listThumbSize: CGSize {
        switch thumbnailSize {
        case 0: return CGSize(width: 52, height: 29)
        case 2: return CGSize(width: 96, height: 54)
        default: return CGSize(width: 68, height: 38)
        }
    }

    /// グリッド列の最小幅（3段階）。
    private var gridMinWidth: CGFloat {
        switch thumbnailSize {
        case 0: return 110
        case 2: return 230
        default: return 160
        }
    }

    private var list: some View {
        List(displayObjects) { object in
            switch object {
            case .container(let container):
                NavigationLink(value: BrowseRoute(server: server, objectID: container.id, title: container.title)) {
                    Label(container.title, systemImage: "folder")
                }
            case .item(let item):
                NavigationLink(value: PlayerRoute(item: item)) {
                    VideoRow(item: item, rating: ratings.rating(for: item), thumbSize: listThumbSize)
                }
                // 左スワイプ（trailing）で評価を選択。
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    ratingButtons(for: item)
                }
                // 長押し（iOS）/ 右クリック（macOS）で評価・ダウンロード。
                .contextMenu {
                    itemMenu(for: item)
                }
            }
        }
        .refreshable { await load(force: true) }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridMinWidth), spacing: 16)], spacing: 16) {
                ForEach(displayObjects) { object in
                    switch object {
                    case .container(let container):
                        NavigationLink(value: BrowseRoute(server: server, objectID: container.id, title: container.title)) {
                            folderTile(container)
                        }
                        .buttonStyle(.plain)
                    case .item(let item):
                        NavigationLink(value: PlayerRoute(item: item)) {
                            videoTile(item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { itemMenu(for: item) }
                    }
                }
            }
            .padding()
        }
        .refreshable { await load(force: true) }
    }

    private func folderTile(_ container: MediaContainer) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text(container.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private func videoTile(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(item: item)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                let rating = ratings.rating(for: item)
                if rating != .none {
                    Image(systemName: rating.symbol)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(rating == .like ? .green : .red, in: Circle())
                        .padding(6)
                }
                // ダウンロード済みは左下に表示。
                if DownloadManager.shared.state(for: item).isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, .green)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            // ダウンロード中はサムネの下にプログレスバー。
            if case .downloading(let progress) = DownloadManager.shared.state(for: item) {
                ProgressView(value: progress)
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
        }
    }

    /// スワイプ用の評価ボタン。
    @ViewBuilder
    private func ratingButtons(for item: MediaItem) -> some View {
        let current = ratings.rating(for: item)
        Button { ratings.set(.like, for: item) } label: {
            Label("Like", systemImage: "hand.thumbsup")
        }.tint(.green)
        Button { ratings.set(.dislike, for: item) } label: {
            Label("Dislike", systemImage: "hand.thumbsdown")
        }.tint(.red)
        if current != .none {
            Button { ratings.set(.none, for: item) } label: {
                Label("クリア", systemImage: "xmark")
            }.tint(.gray)
        }
    }

    /// 長押し（コンテキスト）メニュー本体：評価＋ダウンロード。
    @ViewBuilder
    private func itemMenu(for item: MediaItem) -> some View {
        ratingMenu(for: item)
        Divider()
        downloadMenu(for: item)
    }

    /// ダウンロード関連メニュー。
    @ViewBuilder
    private func downloadMenu(for item: MediaItem) -> some View {
        let downloads = DownloadManager.shared
        switch downloads.state(for: item) {
        case .downloaded:
            if let size = downloads.size(for: item) {
                Text("サイズ: \(formatBytes(size))")
            }
            Button(role: .destructive) { downloads.delete(item) } label: {
                Label("ダウンロードを削除", systemImage: "trash")
            }
        case .downloading(let progress):
            Button { downloads.cancel(item) } label: {
                Label("ダウンロード中… \(Int(progress * 100))%（キャンセル）", systemImage: "stop.circle")
            }
        case .none:
            Button { downloads.download(item) } label: {
                if let size = downloads.size(for: item) {
                    Label("ダウンロード（\(formatBytes(size))）", systemImage: "arrow.down.circle")
                } else {
                    Label("ダウンロード", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    /// コンテキストメニュー用の評価項目（現在の評価にチェック）。
    @ViewBuilder
    private func ratingMenu(for item: MediaItem) -> some View {
        let current = ratings.rating(for: item)
        Picker("評価", selection: Binding(
            get: { current },
            set: { ratings.set($0, for: item) }
        )) {
            Label("Like", systemImage: "hand.thumbsup").tag(Rating.like)
            Label("Dislike", systemImage: "hand.thumbsdown").tag(Rating.dislike)
            Label("評価なし", systemImage: "minus").tag(Rating.none)
        }
    }

    /// フォルダの中身を読み込む。`force == false` ならキャッシュを使う。
    private func load(force: Bool = false) async {
        // キャッシュ利用（再読み込みでない場合）。
        if !force, let cached = BrowseCache.shared.objects(server: server, objectID: objectID) {
            objects = cached
            isLoading = false
            error = nil
            return
        }
        isLoading = true
        error = nil
        guard let controlURL = server.contentDirectoryControlURL else {
            error = "ContentDirectory が見つかりません"
            isLoading = false
            return
        }
        do {
            let result = try await client.browse(controlURL: controlURL, objectID: objectID)
            objects = result.objects
            BrowseCache.shared.store(result.objects, server: server, objectID: objectID)
        } catch {
            self.error = LibraryModel.message(for: error)
        }
        isLoading = false
    }
}

/// 動画アイテム 1 行。
private struct VideoRow: View {
    let item: MediaItem
    let rating: Rating
    var thumbSize: CGSize = CGSize(width: 68, height: 38)

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                ThumbnailView(item: item, size: thumbSize)
                // ダウンロード中はサムネの下にプログレスバー。
                if case .downloading(let progress) = DownloadManager.shared.state(for: item) {
                    ProgressView(value: progress)
                        .frame(width: thumbSize.width)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if DownloadManager.shared.state(for: item).isDownloaded {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if rating != .none {
                Image(systemName: rating.symbol)
                    .foregroundStyle(rating == .like ? .green : .red)
            }
        }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let res = item.preferredVideoResource {
            if let seconds = res.durationSeconds {
                parts.append(Self.formatDuration(seconds))
            }
            if let resolution = res.resolution {
                parts.append(resolution)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
