import Foundation

/// 孤立データの検出結果（種類別の孤立キー一覧）。
public struct OrphanReport: Equatable, Sendable {
    public var ratings: [String]
    public var bookmarks: [String]
    public var tags: [String]
    public var thumbnails: [String]
    public var downloads: [String]

    public init(ratings: [String] = [], bookmarks: [String] = [],
                tags: [String] = [], thumbnails: [String] = [], downloads: [String] = []) {
        self.ratings = ratings
        self.bookmarks = bookmarks
        self.tags = tags
        self.thumbnails = thumbnails
        self.downloads = downloads
    }

    public var total: Int {
        ratings.count + bookmarks.count + tags.count + thumbnails.count + downloads.count
    }
}

/// 各ストアの保存キーのうち、サーバ上に現存する動画（`live`）に無いものを孤立として分類する。
/// `live` はサーバ再スキャンで集めた現存動画の `persistentKey` 集合。
public enum OrphanDetector {
    public static func detect(
        live: Set<String>,
        ratingKeys: Set<String>,
        bookmarkKeys: Set<String>,
        tagKeys: Set<String>,
        thumbnailKeys: Set<String>,
        downloadKeys: Set<String>
    ) -> OrphanReport {
        OrphanReport(
            ratings: ratingKeys.subtracting(live).sorted(),
            bookmarks: bookmarkKeys.subtracting(live).sorted(),
            tags: tagKeys.subtracting(live).sorted(),
            thumbnails: thumbnailKeys.subtracting(live).sorted(),
            downloads: downloadKeys.subtracting(live).sorted()
        )
    }
}
