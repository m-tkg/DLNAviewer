import Foundation
import Testing
import DLNAKit
@testable import DLNAviewer

/// テスト用の MediaItem（persistentKey = "Movie.mp4|d3600|s100"）。
private func makeItem(id: String = "obj-1", title: String = "Movie.mp4") -> MediaItem {
    let res = MediaResource(url: URL(string: "http://x/\(id)")!,
                            durationSeconds: 3600, size: 100)
    return MediaItem(id: id, parentID: "0", title: title,
                     upnpClass: "object.item.videoItem", resources: [res])
}

@MainActor
@Suite("RatingsModel")
struct RatingsModelTests {
    @Test("設定した評価が取得でき、none で消える")
    func setAndGet() {
        let model = RatingsModel(store: RatingStore(storage: InMemoryStorage()))
        let item = makeItem()
        #expect(model.rating(for: item) == .none)

        model.set(.like, for: item)
        #expect(model.rating(for: item) == .like)

        model.set(.none, for: item)
        #expect(model.rating(for: item) == .none)
    }

    @Test("reload でストアの変更（iCloud 同期相当）を取り込む")
    func reloadPicksUpStoreChanges() {
        let store = RatingStore(storage: InMemoryStorage())
        let model = RatingsModel(store: store)
        let item = makeItem()

        store.setRating(.dislike, for: item.persistentKey)   // モデルの外からストアを更新
        #expect(model.rating(for: item) == .none, "キャッシュはまだ古い")

        model.reload()
        #expect(model.rating(for: item) == .dislike)
    }

    @Test("旧キー（object id）の評価が一度だけ新キーへ移行される")
    func migratesLegacyRating() {
        let store = RatingStore(storage: InMemoryStorage())
        store.setRating(.like, for: "obj-1")   // 旧スキームで保存されたデータ
        let model = RatingsModel(store: store)
        let item = makeItem()

        #expect(model.rating(for: item) == .like)
        #expect(store.rating(for: item.persistentKey) == .like, "新キーでストアに永続化される")
    }

    @Test("rating(for:) の参照は監視中の状態を変更しない（View body での無限再描画ループの回帰テスト）")
    func readDoesNotMutateObservedState() {
        let model = RatingsModel(store: RatingStore(storage: InMemoryStorage()))
        let item = makeItem()

        // View body 相当: 監視しながら読む。読み取りが observable な cache への
        // 書き込みを伴うと onChange が発火し、実アプリでは body 再評価の無限ループになる。
        final class Flag: @unchecked Sendable { var invalidated = false }
        let flag = Flag()
        withObservationTracking {
            _ = model.rating(for: item)
        } onChange: {
            flag.invalidated = true
        }
        // 2 回目の参照（再描画相当）。読み取りだけなら何も起きない。
        _ = model.rating(for: item)
        #expect(flag.invalidated == false, "評価の参照だけで View が無効化されてはならない")
    }
}

@MainActor
@Suite("BookmarksModel")
struct BookmarksModelTests {
    @Test("追加・近接重複無視・削除")
    func addAndRemove() {
        let model = BookmarksModel(store: BookmarkStore(storage: InMemoryStorage()))
        let item = makeItem()

        model.add(10, for: item)
        model.add(10.2, for: item)   // 0.4 秒以内は重複扱い
        model.add(30, for: item)
        #expect(model.bookmarks(for: item) == [10, 30])

        model.remove(10, for: item)
        #expect(model.bookmarks(for: item) == [30])
    }
}

@MainActor
@Suite("TagsModel")
struct TagsModelTests {
    @Test("追加・大小無視の重複排除・削除")
    func addAndRemove() {
        let model = TagsModel(store: TagStore(storage: InMemoryStorage()))
        let item = makeItem()

        model.add("Action", for: item)
        model.add("action", for: item)   // 大小無視で重複
        model.add("SF", for: item)
        #expect(model.tags(for: item) == ["Action", "SF"])

        model.remove("ACTION", for: item)
        #expect(model.tags(for: item) == ["SF"])
    }

    @Test("allTags は全動画のタグをユニーク・昇順で返す")
    func allTags() {
        let model = TagsModel(store: TagStore(storage: InMemoryStorage()))
        model.add("b-tag", for: makeItem(id: "1", title: "A.mp4"))
        model.add("a-tag", for: makeItem(id: "2", title: "B.mp4"))
        #expect(model.allTags() == ["a-tag", "b-tag"])
    }
}

@MainActor
@Suite("ThumbnailsModel")
struct ThumbnailsModelTests {
    @Test("設定・クリア")
    func setAndClear() {
        let model = ThumbnailsModel(store: ThumbnailOverrideStore(storage: InMemoryStorage()))
        let item = makeItem()

        model.set(42, for: item)
        #expect(model.time(for: item) == 42)

        model.clear(for: item)
        #expect(model.time(for: item) == nil)
    }
}
