import SwiftUI
import DLNAKit

/// フォルダ（コンテナ）の中身を一覧表示する画面。
struct BrowseView: View {
    let server: MediaServer
    let objectID: String
    let title: String

    @Environment(RatingsModel.self) private var ratings

    @State private var objects: [DIDLObject] = []
    @State private var isLoading = true
    @State private var error: String?

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
                    Button("再試行") { Task { await load() } }
                }
            } else if displayObjects.isEmpty {
                ContentUnavailableView("項目がありません", systemImage: "tray")
            } else {
                list
            }
        }
        .navigationTitle(title)
        .task { await load() }
    }

    /// 表示対象＝コンテナと動画アイテムのみ（動画 DMP のため音声等は除外）。
    private var displayObjects: [DIDLObject] {
        objects.filter { object in
            switch object {
            case .container: return true
            case .item(let item): return item.isVideo
            }
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
                    VideoRow(item: item, rating: ratings.rating(for: item))
                }
                // 左スワイプ（trailing）で評価を選択。
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    ratingButtons(for: item)
                }
                // 長押し（iOS）/ 右クリック（macOS）でも評価できる。
                .contextMenu {
                    ratingMenu(for: item)
                }
            }
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

    private func load() async {
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

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(item: item, size: CGSize(width: 64, height: 40))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
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
