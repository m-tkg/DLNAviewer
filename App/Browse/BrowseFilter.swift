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

    /// 検索・タグ・ブックマークのいずれかで絞り込み中か。
    var isSearching: Bool { false }

    /// 評価フィルタが有効か（いずれかの評価を非表示にしているか）。
    var isRatingFiltering: Bool { false }

    /// 評価フィルタの単一選択（メニュー用）。3 フラグと相互変換する。
    enum Selection: Hashable { case all, like, dislike, none }

    var selection: Selection {
        get { .all }
        set { _ = newValue }
    }

    func allows(_ rating: Rating) -> Bool { true }

    func matches(title: String) -> Bool { true }

    /// フィルタを適用する。動画の評価・ブックマーク有無・タグはクロージャで引く。
    func apply(
        to objects: [DIDLObject],
        rating: (MediaItem) -> Rating,
        hasBookmark: (MediaItem) -> Bool,
        itemTags: (MediaItem) -> [String]
    ) -> [DIDLObject] {
        objects
    }
}
