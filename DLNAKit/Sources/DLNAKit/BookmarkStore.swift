import Foundation

/// 動画ごとのブックマーク（再生位置・秒）を端末ローカルに永続化するストア。
/// キーは安定識別子（UPnP の object id 等）。
public final class BookmarkStore: @unchecked Sendable {
    private let core: JSONStoreCore<[String: [Double]]>

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "videoBookmarks") {
        core = JSONStoreCore(storage: storage, key: key, default: { [:] })
    }

    /// 指定 ID のブックマーク（昇順）。
    public func bookmarks(for id: String) -> [Double] {
        core.read { ($0[id] ?? []).sorted() }
    }

    /// ブックマーク一覧を設定する（空なら削除）。非有限値は除外する。
    public func setBookmarks(_ times: [Double], for id: String) {
        let clean = times.filter { $0.isFinite }.sorted()
        core.mutate { dict in
            dict[id] = clean.isEmpty ? nil : clean
        }
    }

    public func all() -> [String: [Double]] {
        core.read { $0 }
    }
}
