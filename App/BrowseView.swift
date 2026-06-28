import SwiftUI
import DLNAKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// フォルダ（コンテナ）の中身、またはダウンロード済み一覧を表示する画面。
struct BrowseView: View {
    /// フォルダ表示時のサーバー。ダウンロード一覧モードでは nil。
    var server: MediaServer? = nil
    var objectID: String = "0"
    let title: String
    /// true ならサーバーではなくダウンロード済みのローカル一覧を表示する。
    var downloadsMode = false

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
    @State private var searchTags: [TagToken] = []
    @State private var bookmarkedOnly = false
    @State private var showingSettings = false
    @State private var showingTagFilter = false
    @State private var tagEditItem: MediaItem?
    @State private var favorites = FavoritesModel.shared
    @State private var detectingChapters = false
    @State private var chapterRun: ChapterRun?
    @State private var chapterTask: Task<Void, Never>?
    @State private var chapterResult: String?
    @State private var showCopiedToast = false

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
                } else if downloadsMode {
                    ContentUnavailableView("ダウンロードはありません", systemImage: "arrow.down.circle")
                } else {
                    ContentUnavailableView("項目がありません", systemImage: "tray")
                }
            } else if gridMode {
                grid
            } else {
                list
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { searchBar }
        .overlay {
            if detectingChapters, let run = chapterRun {
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
                            chapterTask?.cancel()
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
        .alert("自動チャプター", isPresented: Binding(
            get: { chapterResult != nil }, set: { if !$0 { chapterResult = nil } }
        )) {
            Button("OK") { chapterResult = nil }
        } message: {
            if let chapterResult { Text(chapterResult) }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("評価フィルタ", selection: Binding(
                        get: { ratingFilter }, set: { setRatingFilter($0) }
                    )) {
                        Label("すべて", systemImage: "circle.dashed").tag(RatingFilter.all)
                        Label("Like", systemImage: "hand.thumbsup").tag(RatingFilter.like)
                        Label("Dislike", systemImage: "hand.thumbsdown").tag(RatingFilter.dislike)
                        Label("評価なし", systemImage: "minus").tag(RatingFilter.none)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("フィルタ",
                          systemImage: isFiltering
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
        .task { await load() }
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
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
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

    /// 表示対象。
    /// - タグ指定があればそのタグを持つ動画に絞り込み（フォルダは非表示）。
    /// - キーワードがあればその中から名前で検索。
    /// - 評価フィルタは動画に適用。
    /// 表示元。ダウンロード一覧モードではローカルのダウンロード済みを使う（@Observable で削除も即反映）。
    private var sourceObjects: [DIDLObject] {
        downloadsMode
            ? DownloadManager.shared.downloadedItems().map { DIDLObject.item($0) }
            : objects
    }

    /// いま表示している一覧（検索・フィルタ反映済み）のタイトルをクリップボードへコピーする。
    private func copyDisplayedList() {
        let text = displayObjects.map(\.title).joined(separator: "\n")
        guard !text.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showCopiedToast = false }
        }
    }

    private var displayObjects: [DIDLObject] {
        let tagFilter = Set(searchTags.map { $0.name.lowercased() })
        return sourceObjects.filter { object in
            switch object {
            case .container(let container):
                // タグ指定・ブックマーク絞り込み中はフォルダを出さない。
                return tagFilter.isEmpty && !bookmarkedOnly && matchesSearch(container.title)
            case .item(let item):
                guard item.isVideo, ratingAllowed(ratings.rating(for: item)) else { return false }
                if bookmarkedOnly, BookmarksModel.shared.bookmarks(for: item).isEmpty { return false }
                let itemTags = Set(TagsModel.shared.tags(for: item).map { $0.lowercased() })
                return tagFilter.isSubset(of: itemTags) && matchesSearch(item.title)
            }
        }
    }

    /// 与えられた表示オブジェクト列から動画アイテムだけを抜き出す（前/次移動のプレイリスト用）。
    private func videoItems(from objects: [DIDLObject]) -> [MediaItem] {
        objects.compactMap { object in
            if case .item(let item) = object { return item }
            return nil
        }
    }

    private func ratingAllowed(_ rating: Rating) -> Bool {
        switch rating {
        case .like: return filterLike
        case .dislike: return filterDislike
        case .none: return filterNone
        }
    }

    /// 評価フィルタの単一選択。内部の 3 フラグ（filterLike/Dislike/None）へ写像する。
    private enum RatingFilter: Hashable { case all, like, dislike, none }

    private var ratingFilter: RatingFilter {
        switch (filterLike, filterDislike, filterNone) {
        case (true, false, false): return .like
        case (false, true, false): return .dislike
        case (false, false, true): return .none
        default: return .all
        }
    }

    private func setRatingFilter(_ filter: RatingFilter) {
        switch filter {
        case .all:     (filterLike, filterDislike, filterNone) = (true, true, true)
        case .like:    (filterLike, filterDislike, filterNone) = (true, false, false)
        case .dislike: (filterLike, filterDislike, filterNone) = (false, true, false)
        case .none:    (filterLike, filterDislike, filterNone) = (false, false, true)
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
            || !searchTags.isEmpty || bookmarkedOnly
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
        // displayObjects は重い計算なので 1 回だけ評価し、プレイリストと添字も使い回す。
        let objects = displayObjects
        let videos = videoItems(from: objects)
        let indexByID = videoIndexMap(videos)
        return List(objects) { object in
            switch object {
            case .container(let container):
                if let server {
                    NavigationLink(value: BrowseRoute(server: server, objectID: container.id, title: container.title)) {
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
                            NavigationLink(value: BrowseRoute(server: server, objectID: container.id, title: container.title)) {
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
        .refreshable { await load(force: true) }
    }

    private func folderTile(_ container: MediaContainer) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
                // ブックマークがある動画は左上にアイコン表示。
                if !BookmarksModel.shared.bookmarks(for: item).isEmpty {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 1)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// お気に入り登録済みか（`favorites.folders` を参照するので登録状態の変化で再描画される）。
    private func isFavorite(_ container: MediaContainer) -> Bool {
        guard let server else { return false }
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: container.id)
        return favorites.folders.contains { $0.id == id }
    }

    /// フォルダの長押しメニュー：お気に入り登録/解除。
    @ViewBuilder
    private func folderMenu(_ container: MediaContainer) -> some View {
        if let server {
            Button {
                favorites.toggle(server: server, objectID: container.id, title: container.title)
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
        ratingMenu(for: item)
        Button { tagEditItem = item } label: {
            Label("タグを編集…", systemImage: "tag")
        }
        Button { detectChapters(for: item) } label: {
            Label("自動チャプター作成", systemImage: "list.bullet.indent")
        }
        .disabled(detectingChapters)
        Divider()
        downloadMenu(for: item)
    }

    /// 自動チャプターを検出し、ブックマークとして逐次保存する。
    /// 進捗・件数はリアルタイム反映、キャンセル時は作成途中のチャプターを削除する。
    private func detectChapters(for item: MediaItem) {
        guard !detectingChapters else { return }
        let run = ChapterRun()
        chapterRun = run
        detectingChapters = true

        // 別アプリへ切り替えても約30秒は処理を継続できるよう猶予を確保（iOS）。
        #if canImport(UIKit)
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ChapterDetect") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        #endif

        chapterTask = Task {
            let result = await ChapterDetector.detect(
                item: item,
                onProgress: { fraction in run.progress = fraction },
                onChapter: { time in
                    // 既存ブックマークと重複しない新規分だけ保存・記録（ロールバック対象）。
                    let existed = BookmarksModel.shared.bookmarks(for: item)
                        .contains { abs($0 - time) < 0.4 }
                    BookmarksModel.shared.add(time, for: item)
                    if !existed {
                        run.addedTimes.append(time)
                        run.count = run.addedTimes.count
                    }
                }
            )

            if result.cancelled || Task.isCancelled {
                // キャンセル: この実行で作成したチャプターを取り消す。
                for time in run.addedTimes {
                    BookmarksModel.shared.remove(time, for: item)
                }
                chapterResult = "キャンセルしました（作成途中の \(run.addedTimes.count) 個を削除）。"
            } else if run.addedTimes.isEmpty {
                chapterResult = "チャプターを検出できませんでした。"
            } else {
                let source = result.fromMetadata ? "埋め込みチャプター" : "シーン検出"
                chapterResult = "\(run.addedTimes.count) 個のチャプターをブックマークに保存しました（\(source)）。"
            }

            detectingChapters = false
            chapterRun = nil
            chapterTask = nil
            #if canImport(UIKit)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
            #endif
        }
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
        // ダウンロード一覧モードは取得不要（sourceObjects がローカルを直接参照）。
        if downloadsMode {
            isLoading = false
            error = nil
            return
        }
        guard let server else { isLoading = false; return }
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

/// 検索フォームのタグトークン。
struct TagToken: Identifiable, Hashable {
    var id: String { name }
    let name: String
}

/// 動画アイテム 1 行。
private struct VideoRow: View {
    let item: MediaItem
    let rating: Rating
    var thumbSize: CGSize = CGSize(width: 68, height: 38)

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                ZStack(alignment: .topLeading) {
                    ThumbnailView(item: item, size: thumbSize)
                    // ブックマークがある動画は左上にアイコン表示。
                    if !BookmarksModel.shared.bookmarks(for: item).isEmpty {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .shadow(radius: 1)
                            .padding(3)
                    }
                }
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
                let tags = TagsModel.shared.tags(for: item)
                if !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
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
