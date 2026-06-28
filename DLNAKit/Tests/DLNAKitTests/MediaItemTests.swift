import Foundation
import Testing
@testable import DLNAKit

@Suite("MediaItem.persistentKey")
struct MediaItemPersistentKeyTests {
    private func item(id: String, title: String,
                      duration: Double? = nil, size: Int64? = nil) -> MediaItem {
        let res = MediaResource(url: URL(string: "http://x/\(id)")!,
                                durationSeconds: duration, size: size)
        return MediaItem(id: id, parentID: "0", title: title,
                         upnpClass: "object.item.videoItem", resources: [res])
    }

    @Test("id が変わってもタイトル・尺・サイズが同じなら同一キー")
    func sameAttributesSameKey() {
        let a = item(id: "100", title: "Movie.mp4", duration: 3600, size: 12_345)
        let b = item(id: "999", title: "Movie.mp4", duration: 3600, size: 12_345)
        #expect(a.persistentKey == b.persistentKey)
    }

    @Test("同名でもサイズが違えば別キー")
    func differentSizeDifferentKey() {
        let a = item(id: "1", title: "Movie.mp4", duration: 3600, size: 100)
        let b = item(id: "1", title: "Movie.mp4", duration: 3600, size: 200)
        #expect(a.persistentKey != b.persistentKey)
    }

    @Test("同名・同サイズでも尺が違えば別キー")
    func differentDurationDifferentKey() {
        let a = item(id: "1", title: "Movie.mp4", duration: 3600, size: 100)
        let b = item(id: "1", title: "Movie.mp4", duration: 1800, size: 100)
        #expect(a.persistentKey != b.persistentKey)
    }

    @Test("尺は秒に丸める（小数の揺れを無視）")
    func roundsDuration() {
        let a = item(id: "1", title: "Movie.mp4", duration: 3600.2, size: 100)
        let b = item(id: "2", title: "Movie.mp4", duration: 3599.8, size: 100)
        #expect(a.persistentKey == b.persistentKey)
    }

    @Test("尺・サイズが無ければタイトルのみ（自然劣化）")
    func degradesToTitle() {
        let a = item(id: "100", title: "Movie.mp4")
        let b = item(id: "999", title: "Movie.mp4")
        #expect(a.persistentKey == b.persistentKey)
        #expect(a.persistentKey == "Movie.mp4")
    }

    @Test("前後の空白は無視・空タイトルは id")
    func titleNormalization() {
        #expect(item(id: "1", title: "  Movie.mp4 ").persistentKey == "Movie.mp4")
        #expect(item(id: "42", title: "   ").persistentKey.hasPrefix("42"))
    }

    @Test("移行元キーにはタイトルのみ・id が含まれる")
    func legacyKeys() {
        let i = item(id: "42", title: "Movie.mp4", duration: 10, size: 5)
        #expect(i.legacyPersistentKeys == ["Movie.mp4", "42"])
    }
}
