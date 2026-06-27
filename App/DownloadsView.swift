import SwiftUI
import DLNAKit

/// ダウンロード済みの動画一覧。サーバーを介さずローカルから再生できる。
struct DownloadsView: View {
    private let downloads = DownloadManager.shared

    var body: some View {
        let items = downloads.downloadedItems()
        Group {
            if items.isEmpty {
                ContentUnavailableView("ダウンロードはありません", systemImage: "arrow.down.circle")
            } else {
                List(items) { item in
                    NavigationLink(value: PlayerRoute(item: item)) {
                        HStack(spacing: 12) {
                            ThumbnailView(item: item, size: CGSize(width: 68, height: 38))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                if let size = downloads.size(for: item) {
                                    Text(formatBytes(size))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            downloads.delete(item)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            downloads.delete(item)
                        } label: {
                            Label("ダウンロードを削除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("ダウンロード済み")
    }
}
