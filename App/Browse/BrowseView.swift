import SwiftUI
import DLNAKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// フォルダ（コンテナ）の中身、またはダウンロード済み一覧を表示する画面。
/// 読み込み・パス再解決は `BrowseViewModel`、絞り込みは `BrowseFilter`、
/// チャプター検出の実行管理は `ChapterDetectionRunner` に委譲し、この View は描画に徹する。
struct BrowseView: View {
    /// フォルダ表示時のサーバー。ダウンロード一覧モードでは nil。
    let server: MediaServer?
    let title: String
    /// ルート直下からこのフォルダまでのフォルダ名（お気に入りのパス再解決用）。
    let path: [String]
    /// true ならサーバーではなくダウンロード済みのローカル一覧を表示する。
    let downloadsMode: Bool

    @State private var model: BrowseViewModel

    init(server: MediaServer? = nil, objectID: String = "0", title: String,
         path: [String] = [], resolveByPath: Bool = false, downloadsMode: Bool = false) {
        self.server = server
        self.title = title
        self.path = path
        self.downloadsMode = downloadsMode
        _model = State(initialValue: BrowseViewModel(
            server: server, objectID: objectID, title: title,
            path: path, resolveByPath: resolveByPath, downloadsMode: downloadsMode
        ))
    }

    private var ratings: RatingsModel { RatingsModel.shared }
    @AppStorage("browseGridMode") private var gridMode = false
    // 評価フィルタ（ファイルのみ対象。フォルダは常に表示）。
    @AppStorage("filterLike") private var filterLike = true
    @AppStorage("filterDislike") private var filterDislike = true
    @AppStorage("filterNone") private var filterNone = true

    @State private var searchText = ""
    @State private var searchTags: [TagToken] = []
    @State private var bookmarkedOnly = false
    @State private var showingSettings = false
    @State private var showingTagFilter = false
    @State private var tagEditItem: MediaItem?
    @State private var favorites = FavoritesModel.shared
    @State private var chapterRunner = ChapterDetectionRunner()
    @State private var showCopiedToast = false

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("読み込み中…")
            } else if let error = model.error {
                ContentUnavailableView {
                    Label("読み込めません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("再試行") { Task { await model.load(force: true) } }
                }
            } else if displayObjects.isEmpty {
                // 空のときもプルで再読み込みできるよう ScrollView に載せる。
                ScrollView {
                    Group {
                        if filter.isSearching {
                            ContentUnavailableView.search(text: searchText)
                        } else if filter.isRatingFiltering {
                            ContentUnavailableView {
                                Label("該当する項目がありません", systemImage: "line.3.horizontal.decrease.circle")
                            } description: {
                                Text("評価フィルタを変更してください。")
                            }
                        } else if downloadsMode {
                            ContentUnavailableView("ダウンロードはありません", systemImage: "arrow.down.circle")
                        } else {
                            ContentUnavailableView("項目がありません", systemImage: "tray")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 480)
                }
                .refreshable { await model.load(force: true) }
            } else if gridMode {
                grid
            } else {
                list
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { searchBar }
        .overlay {
            if chapterRunner.isRunning, let run = chapterRunner.run {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Text("チャプターを解析中…").font(.callout)
                        ProgressView(value: run.progress)
                            .frame(width: 200)
                        HStack(spacing: 6) {
                            Text("\(Int(run.progress * 100))%")
                            Text("·")
                            Image(systemName: "bookmark.fill").foregroundStyle(.yellow)
                            Text("\(run.count) 個")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        Button(role: .cancel) {
                            chapterRunner.cancel()
                        } label: {
                            Label("キャンセル", systemImage: "xmark.circle")
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("一覧をコピーしました")
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .alert("自動チャプター", isPresented: Binding(presenting: Bindable(chapterRunner).result)) {
            Button("OK") { chapterRunner.result = nil }
        } message: {
            if let message = chapterRunner.result { Text(message) }
        }
        .navigationTitle(title)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("評価フィルタ", selection: Binding(
                        get: { filter.selection }, set: { setRatingSelection($0) }
                    )) {
                        Label("すべて", systemImage: "circle.dashed").tag(BrowseFilter.Selection.all)
                        Label("Like", systemImage: "hand.thumbsup").tag(BrowseFilter.Selection.like)
                        Label("Dislike", systemImage: "hand.thumbsdown").tag(BrowseFilter.Selection.dislike)
                        Label("評価なし", systemImage: "minus").tag(BrowseFilter.Selection.none)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("フィルタ",
                          systemImage: filter.isRatingFiltering
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // タップで表示切替、長押し（iOS）/メニュー（macOS）で一覧をコピー。
                // ツールバーボタンでは .contextMenu / .onLongPressGesture が iOS で効かないため
                // primaryAction 付き Menu を使う（タップ=主アクション・長押し=メニュー）。
                Menu {
                    Button {
                        copyDisplayedList()
                    } label: {
                        Label("一覧をコピー", systemImage: "doc.on.doc")
                    }
                } label: {
                    Label(gridMode ? "リスト表示" : "アイコン表示",
                          systemImage: gridMode ? "list.bullet" : "square.grid.2x2")
                } primaryAction: {
                    gridMode.toggle()
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
        .sheet(item: $tagEditItem) { item in
            TagEditorView(item: item, folderName: title)
        }
        .sheet(isPresented: $showingTagFilter) {
            TagFilterView { tag in
                if !searchTags.contains(where: { $0.name.lowercased() == tag.lowercased() }) {
                    searchTags.append(TagToken(name: tag))
                }
            }
        }
        .task { await model.load() }
        .onDisappear { chapterRunner.cancel() }
    }

    /// 検索フォーム＋右隣のタグ追加ボタン（上部固定）。
    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("検索（正規表現可）", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .noAutocapitalization()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                // ブックマークがある動画だけに絞り込むトグル。
                Button {
                    bookmarkedOnly.toggle()
                } label: {
                    Image(systemName: bookmarkedOnly ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                        .foregroundStyle(bookmarkedOnly ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                // 検索フォームの右隣: タグ指定ボタン（検索・リネーム・削除つき）。
                Button {
                    showingTagFilter = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }

            // 選択中の絞り込み条件のチップ（タップで解除）。
            if !searchTags.isEmpty || bookmarkedOnly {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if bookmarkedOnly {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark.fill").font(.caption2)
                                Text("ブックマークあり").font(.caption)
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.yellow.opacity(0.25), in: Capsule())
                            .onTapGesture { bookmarkedOnly = false }
                        }
                        ForEach(searchTags) { token in
                            HStack(spacing: 4) {
                                Text("#\(token.name)").font(.caption)
                                Image(systemName: "xmark.circle.fill").font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.2), in: Capsule())
                            .onTapGesture { searchTags.removeAll { $0.id == token.id } }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// 表示元。ダウンロード一覧モードではローカルのダウンロード済みを使う（@Observable で削除も即反映）。
    private var sourceObjects: [DIDLObject] {
        downloadsMode
            ? DownloadManager.shared.downloadedItems().map { DIDLObject.item($0) }
            : model.objects
    }

    /// いま表示している一覧（検索・フィルタ反映済み）のタイトルをクリップボードへコピーする。
    private func copyDisplayedList() {
        let text = displayObjects.map(\.title).joined(separator: "\n")
        guard !text.isEmpty else { return }
        Pasteboard.copy(text)
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopiedToast = false }
        }
    }

    /// 現在の検索・タグ・評価・ブックマーク条件（純ロジックは BrowseFilter 側）。
    private var filter: BrowseFilter {
        BrowseFilter(
            query: searchText,
            tags: Set(searchTags.map { $0.name.lowercased() }),
            bookmarkedOnly: bookmarkedOnly,
            allowLike: filterLike, allowDislike: filterDislike, allowNone: filterNone
        )
    }

    /// 表示対象（検索・タグ・評価・ブックマーク絞り込みを反映）。
    /// body から評価・タグ等のモデルを読むので @Observable の変更追跡はそのまま効く。
    private var displayObjects: [DIDLObject] {
        filter.apply(
            to: sourceObjects,
            rating: { ratings.rating(for: $0) },
            hasBookmark: { !BookmarksModel.shared.bookmarks(for: $0).isEmpty },
            itemTags: { TagsModel.shared.tags(for: $0) }
        )
    }

    /// 評価フィルタの選択を @AppStorage の 3 フラグへ書き戻す。
    private func setRatingSelection(_ selection: BrowseFilter.Selection) {
        var f = BrowseFilter()
        f.selection = selection
        (filterLike, filterDislike, filterNone) = (f.allowLike, f.allowDislike, f.allowNone)
    }

    /// 与えられた表示オブジェクト列から動画アイテムだけを抜き出す（前/次移動のプレイリスト用）。
    private func videoItems(from objects: [DIDLObject]) -> [MediaItem] {
        objects.compactMap { object in
            if case .item(let item) = object { return item }
            return nil
        }
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
        // displayObjects は重い計算なので 1 回だけ評価し、プレイリストと添字も使い回す。
        let objects = displayObjects
        let videos = videoItems(from: objects)
        let indexByID = videoIndexMap(videos)
        return List(objects) { object in
            switch object {
            case .container(let container):
                if let server {
                    NavigationLink(value: BrowseRoute(server: server, objectID: container.id, title: container.title, path: path + [container.title])) {
                        HStack {
                            Label(container.title, systemImage: "folder")
                            if isFavorite(container) {
                                Spacer()
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                            }
                        }
                    }
                    .contextMenu { folderMenu(container) }
                }
            case .item(let item):
                NavigationLink(value: PlayerRoute(items: videos, index: indexByID[item.id] ?? 0)) {
                    VideoRow(item: item, rating: ratings.rating(for: item), thumbSize: listThumbSize)
                }
                // 左スワイプ（trailing）で評価を選択。
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    RatingSwipeButtons(item: item, ratings: ratings)
                }
                // 長押し（iOS）/ 右クリック（macOS）で評価・ダウンロード。
                .contextMenu {
                    itemMenu(for: item)
                }
            }
        }
        .refreshable { await model.load(force: true) }
    }

    /// 動画アイテム配列を id→添字の辞書にする（前/次移動の開始位置を O(1) で引くため）。
    private func videoIndexMap(_ videos: [MediaItem]) -> [String: Int] {
        Dictionary(videos.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var grid: some View {
        let objects = displayObjects
        let videos = videoItems(from: objects)
        let indexByID = videoIndexMap(videos)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: gridMinWidth), spacing: 16)], spacing: 16) {
                ForEach(objects) { object in
                    switch object {
                    case .container(let container):
                        if let server {
                            NavigationLink(value: BrowseRoute(server: server, objectID: container.id, title: container.title, path: path + [container.title])) {
                                folderTile(container)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { folderMenu(container) }
                        }
                    case .item(let item):
                        NavigationLink(value: PlayerRoute(items: videos, index: indexByID[item.id] ?? 0)) {
                            videoTile(item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { itemMenu(for: item) }
                    }
                }
            }
            .padding()
        }
        .refreshable { await model.load(force: true) }
    }

    private func folderTile(_ container: MediaContainer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // 動画タイルのサムネ枠と同じ寸法計算にして高さを揃える。
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                    }
                if isFavorite(container) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(6)
                }
            }
            Text(container.title)
                .font(.caption)
                .lineLimit(2)
        }
    }

    private func videoTile(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // フォルダタイルと同じ寸法計算にして高さを揃える。
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay { ThumbnailView(item: item) }
                let rating = ratings.rating(for: item)
                if rating != .none {
                    Image(systemName: rating.symbol)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(rating == .like ? .green : .red, in: Circle())
                        .padding(6)
                }
                // ブックマークがある動画は左上にアイコン表示。
                if !BookmarksModel.shared.bookmarks(for: item).isEmpty {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 1)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                // 左下: ダウンロード済みアイコン＋タグ（入る分だけ、はみ出しは … で省略）。
                let tags = TagsModel.shared.tags(for: item)
                let downloaded = DownloadManager.shared.state(for: item).isDownloaded
                if downloaded || !tags.isEmpty {
                    HStack(spacing: 4) {
                        if downloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white, .green)
                        }
                        if !tags.isEmpty {
                            TagOverflowRow(tags: tags)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
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

    /// お気に入り登録済みか（`favorites.folders` を参照するので登録状態の変化で再描画される）。
    private func isFavorite(_ container: MediaContainer) -> Bool {
        guard let server else { return false }
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: container.id, title: container.title)
        return favorites.folders.contains { $0.id == id }
    }

    /// フォルダの長押しメニュー：お気に入り登録/解除。
    @ViewBuilder
    private func folderMenu(_ container: MediaContainer) -> some View {
        if let server {
            Button {
                favorites.toggle(server: server, objectID: container.id, title: container.title, path: path + [container.title])
            } label: {
                if isFavorite(container) {
                    Label("お気に入り解除", systemImage: "star.slash")
                } else {
                    Label("お気に入りに追加", systemImage: "star")
                }
            }
        }
    }

    /// 長押し（コンテキスト）メニュー本体：評価＋ダウンロード。
    @ViewBuilder
    private func itemMenu(for item: MediaItem) -> some View {
        RatingMenu(item: item, ratings: ratings)
        Button { tagEditItem = item } label: {
            Label("タグを編集…", systemImage: "tag")
        }
        Button { chapterRunner.detect(item: item) } label: {
            Label("自動チャプター作成", systemImage: "list.bullet.indent")
        }
        .disabled(chapterRunner.isRunning)
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

}
