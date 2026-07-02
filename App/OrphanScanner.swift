import Foundation
import DLNAKit

/// 全登録サーバを再スキャンし、サーバ上に現存しない動画のデータ（孤立）を検出する。
///
/// 安全策: 1 台でもサーバに到達できなかった場合は `allReachable = false` とし、呼び出し側は
/// 削除を行わない（オフラインのサーバの動画を「消えた」と誤判定して大量削除するのを防ぐ）。
@MainActor
final class OrphanScanner {
    struct Outcome {
        var report: OrphanReport
        /// すべての登録サーバを最後まで走査できたか。false の場合は削除してはならない。
        var allReachable: Bool
    }

    private let client = ContentDirectoryClient()
    /// 再帰中に訪問済みの「controlURL#objectID」。サイクル遮断用。
    private var visited = Set<String>()

    /// サーバを再帰ブラウズして現存動画の persistentKey を集め、各ストアのキーと照合する。
    func scan(servers: [MediaServer]) async -> Outcome {
        visited.removeAll()
        var live = Set<String>()
        var allReachable = true
        for server in servers {
            guard let controlURL = server.contentDirectoryControlURL else { continue }
            do {
                live.formUnion(try await collect(controlURL: controlURL, objectID: "0", depth: 0))
            } catch {
                // このサーバは到達不能。誤検出を避けるため削除不可フラグを立てる。
                allReachable = false
            }
        }
        let report = OrphanDetector.detect(
            live: live,
            ratingKeys: Set(RatingStore().all().keys),
            bookmarkKeys: Set(BookmarkStore().all().keys),
            tagKeys: Set(TagStore().all().keys),
            thumbnailKeys: Set(ThumbnailOverrideStore().all().keys),
            downloadKeys: DownloadManager.shared.downloadKeys()
        )
        return Outcome(report: report, allReachable: allReachable)
    }

    /// 検出した孤立データを各ストアから削除し、関係するモデルを再読込する。
    func removeOrphans(_ report: OrphanReport) {
        let rating = RatingStore()
        for k in report.ratings { rating.setRating(.none, for: k) }
        let bookmark = BookmarkStore()
        for k in report.bookmarks { bookmark.setBookmarks([], for: k) }
        let tag = TagStore()
        for k in report.tags { tag.setTags([], for: k) }
        let thumbnail = ThumbnailOverrideStore()
        for k in report.thumbnails { thumbnail.setTime(nil, for: k) }
        DownloadManager.shared.removeDownloads(persistentKeys: Set(report.downloads))
        DownloadManager.shared.removeOrphans()   // 記録と実ファイルの不整合も併せて掃除
        // モデルのキャッシュを更新する。
        CloudSync.reloadAllModels()
    }

    /// 1 フォルダ配下を再帰的に走査し、動画の persistentKey 集合を返す。
    private func collect(controlURL: URL, objectID: String, depth: Int) async throws -> Set<String> {
        try Task.checkCancellation()
        // 不正なサーバのコンテナ循環や過大な深さで無限再帰しないよう防ぐ。
        guard depth < 64 else { return [] }
        let visitKey = "\(controlURL.absoluteString)#\(objectID)"
        guard visited.insert(visitKey).inserted else { return [] }
        var keys = Set<String>()
        let objects = try await client.browseAll(controlURL: controlURL, objectID: objectID)
        for obj in objects {
            switch obj {
            case .container(let container):
                keys.formUnion(try await collect(controlURL: controlURL, objectID: container.id, depth: depth + 1))
            case .item(let item):
                keys.insert(item.persistentKey)
            }
        }
        return keys
    }
}
