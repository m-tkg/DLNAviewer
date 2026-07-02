import Foundation
import Testing
import DLNAKit
@testable import DLNAviewer

@Suite("BrowseFilter")
struct BrowseFilterTests {
    private func video(_ id: String, title: String) -> MediaItem {
        MediaItem(id: id, parentID: "0", title: title,
                  upnpClass: "object.item.videoItem",
                  resources: [MediaResource(url: URL(string: "http://x/\(id)")!)])
    }
    private func folder(_ id: String, title: String) -> MediaContainer {
        MediaContainer(id: id, parentID: "0", title: title, childCount: 0)
    }

    /// フォルダ 1 つ + 動画 2 つの標準セット。
    private var objects: [DIDLObject] {
        [.container(folder("f", title: "Folder")),
         .item(video("a", title: "Alpha.mp4")),
         .item(video("b", title: "Beta.mp4"))]
    }

    private func apply(_ filter: BrowseFilter,
                       to objects: [DIDLObject],
                       ratings: [String: Rating] = [:],
                       bookmarks: Set<String> = [],
                       tags: [String: [String]] = [:]) -> [String] {
        filter.apply(
            to: objects,
            rating: { ratings[$0.id] ?? .none },
            hasBookmark: { bookmarks.contains($0.id) },
            itemTags: { tags[$0.id] ?? [] }
        ).map(\.title)
    }

    @Test("検索は大小無視の部分一致（フォルダにも効く）")
    func searchCaseInsensitive() {
        var filter = BrowseFilter()
        filter.query = "alpha"
        #expect(apply(filter, to: objects) == ["Alpha.mp4"])
        filter.query = "FOLD"
        #expect(apply(filter, to: objects) == ["Folder"])
    }

    @Test("検索は正規表現として解釈される")
    func searchRegex() {
        var filter = BrowseFilter()
        filter.query = "^(Alpha|Beta)"
        #expect(apply(filter, to: objects) == ["Alpha.mp4", "Beta.mp4"])
    }

    @Test("無効な正規表現は部分一致にフォールバック")
    func invalidRegexFallsBack() {
        var filter = BrowseFilter()
        filter.query = "beta.mp4("   // 開き括弧のみ → 正規表現として無効
        #expect(apply(filter, to: [.item(video("x", title: "beta.mp4("))]) == ["beta.mp4("])
    }

    @Test("タグ絞り込みは AND 条件・大小無視で、フォルダを隠す")
    func tagFilterAndSemantics() {
        var filter = BrowseFilter()
        filter.tags = ["action", "sf"]
        let tags = ["a": ["Action", "SF"], "b": ["Action"]]
        #expect(apply(filter, to: objects, tags: tags) == ["Alpha.mp4"])
    }

    @Test("ブックマーク絞り込みはフォルダを隠し、ブックマークのある動画だけ残す")
    func bookmarkedOnly() {
        var filter = BrowseFilter()
        filter.bookmarkedOnly = true
        #expect(apply(filter, to: objects, bookmarks: ["b"]) == ["Beta.mp4"])
    }

    @Test("評価フィルタは動画のみ対象でフォルダは常に表示")
    func ratingFilter() {
        var filter = BrowseFilter()
        filter.selection = .like
        let ratings: [String: Rating] = ["a": .like, "b": .dislike]
        #expect(apply(filter, to: objects, ratings: ratings) == ["Folder", "Alpha.mp4"])
    }

    @Test("Selection と 3 フラグの相互変換")
    func selectionMapping() {
        var filter = BrowseFilter()
        #expect(filter.selection == .all)

        filter.selection = .dislike
        #expect((filter.allowLike, filter.allowDislike, filter.allowNone) == (false, true, false))
        #expect(filter.isRatingFiltering)

        filter.selection = .all
        #expect((filter.allowLike, filter.allowDislike, filter.allowNone) == (true, true, true))
        #expect(!filter.isRatingFiltering)
    }

    @Test("isSearching は検索・タグ・ブックマークのいずれかで true")
    func isSearching() {
        var filter = BrowseFilter()
        #expect(!filter.isSearching)
        filter.query = "  "   // 空白のみは検索中と見なさない
        #expect(!filter.isSearching)
        filter.query = "a"
        #expect(filter.isSearching)
        filter = BrowseFilter(bookmarkedOnly: true)
        #expect(filter.isSearching)
    }

    @Test("動画以外のアイテム（音声等）は表示しない")
    func nonVideoItemsHidden() {
        let audio = MediaItem(id: "m", parentID: "0", title: "Music.mp3",
                              upnpClass: "object.item.audioItem",
                              resources: [MediaResource(url: URL(string: "http://x/m")!)])
        #expect(apply(BrowseFilter(), to: [.item(audio)]) == [])
    }
}
