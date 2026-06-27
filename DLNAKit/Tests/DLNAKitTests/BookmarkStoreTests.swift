import Foundation
import Testing
@testable import DLNAKit

@Suite("BookmarkStore")
struct BookmarkStoreTests {
    @Test("追加・取得（昇順）")
    func setAndGet() {
        let store = BookmarkStore(storage: MemoryStorage(), key: "test")
        store.setBookmarks([120, 30, 75], for: "a")
        #expect(store.bookmarks(for: "a") == [30, 75, 120])
    }

    @Test("空で削除")
    func clearing() {
        let store = BookmarkStore(storage: MemoryStorage(), key: "test")
        store.setBookmarks([10], for: "a")
        store.setBookmarks([], for: "a")
        #expect(store.bookmarks(for: "a").isEmpty)
        #expect(store.all().isEmpty)
    }

    @Test("永続化が共有される")
    func persists() {
        let storage = MemoryStorage()
        BookmarkStore(storage: storage, key: "test").setBookmarks([42], for: "a")
        #expect(BookmarkStore(storage: storage, key: "test").bookmarks(for: "a") == [42])
    }
}
