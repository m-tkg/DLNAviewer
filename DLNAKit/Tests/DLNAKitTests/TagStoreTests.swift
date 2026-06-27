import Foundation
import Testing
@testable import DLNAKit

@Suite("TagStore")
struct TagStoreTests {
    @Test("追加・取得（昇順）")
    func setAndGet() {
        let store = TagStore(storage: MemoryStorage(), key: "test")
        store.setTags(["travel", "family", "beach"], for: "a")
        #expect(store.tags(for: "a") == ["beach", "family", "travel"])
        #expect(store.tags(for: "b").isEmpty)
    }

    @Test("重複（大小無視）・空白を整理")
    func dedupe() {
        let store = TagStore(storage: MemoryStorage(), key: "test")
        store.setTags([" Trip ", "trip", "", "Beach"], for: "a")
        #expect(store.tags(for: "a") == ["Beach", "Trip"])
    }

    @Test("空で削除")
    func clearing() {
        let store = TagStore(storage: MemoryStorage(), key: "test")
        store.setTags(["x"], for: "a")
        store.setTags([], for: "a")
        #expect(store.tags(for: "a").isEmpty)
        #expect(store.all().isEmpty)
    }

    @Test("永続化が共有される")
    func persists() {
        let storage = MemoryStorage()
        TagStore(storage: storage, key: "test").setTags(["movie"], for: "a")
        #expect(TagStore(storage: storage, key: "test").tags(for: "a") == ["movie"])
    }
}
