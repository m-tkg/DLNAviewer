import Foundation
import Testing
@testable import DLNAKit

@Suite("MediaItem.persistentKey")
struct MediaItemPersistentKeyTests {
    private func item(id: String, title: String) -> MediaItem {
        MediaItem(id: id, parentID: "0", title: title, upnpClass: "object.item.videoItem", resources: [])
    }

    @Test("id が変わってもタイトルが同じなら同一キー")
    func sameTitleSameKey() {
        let a = item(id: "100", title: "Movie.mp4")
        let b = item(id: "999", title: "Movie.mp4")
        #expect(a.persistentKey == b.persistentKey)
    }

    @Test("前後の空白は無視")
    func trimsWhitespace() {
        #expect(item(id: "1", title: "  Movie.mp4 ").persistentKey == "Movie.mp4")
    }

    @Test("空タイトルは id にフォールバック")
    func emptyTitleFallsBackToID() {
        #expect(item(id: "42", title: "   ").persistentKey == "42")
    }

    @Test("異なるタイトルは別キー")
    func differentTitleDifferentKey() {
        #expect(item(id: "1", title: "A.mp4").persistentKey != item(id: "1", title: "B.mp4").persistentKey)
    }
}
