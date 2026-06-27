import Foundation
import Testing
@testable import DLNAKit

@Suite("RatingStore")
struct RatingStoreTests {
    @Test("未設定は none")
    func defaultsToNone() {
        let store = RatingStore(storage: MemoryStorage(), key: "test")
        #expect(store.rating(for: "64$1") == .none)
    }

    @Test("like/dislike を設定・取得できる")
    func setAndGet() {
        let store = RatingStore(storage: MemoryStorage(), key: "test")
        store.setRating(.like, for: "a")
        store.setRating(.dislike, for: "b")
        #expect(store.rating(for: "a") == .like)
        #expect(store.rating(for: "b") == .dislike)
    }

    @Test("none を設定するとレコードが消える")
    func clearing() {
        let store = RatingStore(storage: MemoryStorage(), key: "test")
        store.setRating(.like, for: "a")
        store.setRating(.none, for: "a")
        #expect(store.rating(for: "a") == .none)
        #expect(store.all().isEmpty)
    }

    @Test("別インスタンスでも永続化が共有される")
    func persists() {
        let storage = MemoryStorage()
        RatingStore(storage: storage, key: "test").setRating(.like, for: "a")
        #expect(RatingStore(storage: storage, key: "test").rating(for: "a") == .like)
    }
}
