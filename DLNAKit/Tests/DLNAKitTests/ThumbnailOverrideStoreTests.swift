import Foundation
import Testing
@testable import DLNAKit

@Suite("ThumbnailOverrideStore")
struct ThumbnailOverrideStoreTests {
    @Test("設定・取得")
    func setAndGet() {
        let store = ThumbnailOverrideStore(storage: MemoryStorage(), key: "test")
        store.setTime(123.5, for: "a")
        #expect(store.time(for: "a") == 123.5)
        #expect(store.time(for: "b") == nil)
    }

    @Test("nil/非有限で削除・無視")
    func clearing() {
        let store = ThumbnailOverrideStore(storage: MemoryStorage(), key: "test")
        store.setTime(10, for: "a")
        store.setTime(nil, for: "a")
        #expect(store.time(for: "a") == nil)
        store.setTime(.nan, for: "a")
        #expect(store.time(for: "a") == nil)
    }

    @Test("永続化が共有される")
    func persists() {
        let storage = MemoryStorage()
        ThumbnailOverrideStore(storage: storage, key: "test").setTime(42, for: "a")
        #expect(ThumbnailOverrideStore(storage: storage, key: "test").time(for: "a") == 42)
    }
}
