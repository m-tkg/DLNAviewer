import Foundation
import DLNAKit

/// 一覧の検索・タグ・評価・ブックマーク絞り込み（純ロジック）。
/// BrowseView の body に埋まっていたフィルタ処理を切り出したもの。
/// モデル参照はクロージャ注入（body から呼べば @Observable の追跡はそのまま効く）。
struct BrowseFilter {
    /// 検索文字列。正規表現として解釈し、無効なら部分一致にフォールバック。
    var query = ""
    /// 絞り込みタグ（AND 条件・小文字比較）。指定中はフォルダを表示しない。
    var tags: Set<String> = []
    /// ブックマークのある動画だけに絞る。指定中はフォルダを表示しない。
    var bookmarkedOnly = false
    /// 評価フィルタ（動画のみ対象。フォルダは常に表示）。
    var allowLike = true
    var allowDislike = true
    var allowNone = true

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 検索・タグ・ブックマークのいずれかで絞り込み中か。
    var isSearching: Bool {
        !trimmedQuery.isEmpty || !tags.isEmpty || bookmarkedOnly
    }

    /// 評価フィルタが有効か（いずれかの評価を非表示にしているか）。
    var isRatingFiltering: Bool {
        !(allowLike && allowDislike && allowNone)
    }

    /// 評価フィルタの単一選択（メニュー用）。3 フラグと相互変換する。
    enum Selection: Hashable { case all, like, dislike, none }

    var selection: Selection {
        get {
            switch (allowLike, allowDislike, allowNone) {
            case (true, false, false): return .like
            case (false, true, false): return .dislike
            case (false, false, true): return .none
            default: return .all
            }
        }
        set {
            switch newValue {
            case .all:     (allowLike, allowDislike, allowNone) = (true, true, true)
            case .like:    (allowLike, allowDislike, allowNone) = (true, false, false)
            case .dislike: (allowLike, allowDislike, allowNone) = (false, true, false)
            case .none:    (allowLike, allowDislike, allowNone) = (false, false, true)
            }
        }
    }

    func allows(_ rating: Rating) -> Bool {
        switch rating {
        case .like: return allowLike
        case .dislike: return allowDislike
        case .none: return allowNone
        }
    }

    /// 検索文字列にマッチするか。正規表現として解釈し、無効なら部分一致にフォールバック。
    func matches(title: String) -> Bool {
        let query = trimmedQuery
        guard !query.isEmpty else { return true }
        if let regex = try? Regex(query).ignoresCase() {
            return title.contains(regex)
        }
        return title.localizedCaseInsensitiveContains(query)
    }

    /// フィルタを適用する。動画の評価・ブックマーク有無・タグはクロージャで引く。
    func apply(
        to objects: [DIDLObject],
        rating: (MediaItem) -> Rating,
        hasBookmark: (MediaItem) -> Bool,
        itemTags: (MediaItem) -> [String]
    ) -> [DIDLObject] {
        objects.filter { object in
            switch object {
            case .container(let container):
                // タグ指定・ブックマーク絞り込み中はフォルダを出さない。
                return tags.isEmpty && !bookmarkedOnly && matches(title: container.title)
            case .item(let item):
                guard item.isVideo, allows(rating(item)) else { return false }
                if bookmarkedOnly, !hasBookmark(item) { return false }
                let lowered = Set(itemTags(item).map { $0.lowercased() })
                return tags.isSubset(of: lowered) && matches(title: item.title)
            }
        }
    }
}
