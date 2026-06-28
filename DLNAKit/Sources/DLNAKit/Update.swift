import Foundation

/// GitHub `/repos/{owner}/{repo}/releases/latest` のレスポンス（必要フィールドのみ）。
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    public let tagName: String
    public let htmlUrl: String
    public let assets: [Asset]

    /// リリースに添付されたアセット（ダウンロード対象）。
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let browserDownloadUrl: String

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }

        public init(name: String, browserDownloadUrl: String) {
            self.name = name
            self.browserDownloadUrl = browserDownloadUrl
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }

    public init(tagName: String, htmlUrl: String, assets: [Asset] = []) {
        self.tagName = tagName
        self.htmlUrl = htmlUrl
        self.assets = assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tagName = try container.decode(String.self, forKey: .tagName)
        self.htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        self.assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    /// 最初の `.zip` アセットのダウンロード URL。
    public var zipAssetURL: URL? {
        assets.first { $0.name.hasSuffix(".zip") }
            .flatMap { URL(string: $0.browserDownloadUrl) }
    }
}

/// `v` プレフィックス付きのタグと `CFBundleShortVersionString` を数値比較する。
public enum VersionComparator {
    /// `tag` が `current` より新しければ true。
    public static func isNewer(tag: String, than current: String) -> Bool {
        let a = components(tag)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 先頭の `v`/`V` を除去し `.` 区切りで数値化。各要素は先頭の数字部分のみ採用（`2-beta` → 2）。
    private static func components(_ version: String) -> [Int] {
        let trimmed = (version.hasPrefix("v") || version.hasPrefix("V"))
            ? String(version.dropFirst())
            : version
        return trimmed.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}
