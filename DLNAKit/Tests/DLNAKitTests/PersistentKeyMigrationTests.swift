import Foundation
import Testing
@testable import DLNAKit

@Suite("PersistentKeyMigration")
struct PersistentKeyMigrationTests {
    /// persistentKey = "Movie.mp4|d3600|s100"、legacy = ["Movie.mp4", "obj-1"]。
    private func item() -> MediaItem {
        let res = MediaResource(url: URL(string: "http://x/1")!,
                                durationSeconds: 3600, size: 100)
        return MediaItem(id: "obj-1", parentID: "0", title: "Movie.mp4",
                         upnpClass: "object.item.videoItem", resources: [res])
    }

    @Test("新キーの値が既にあれば移行せずそのまま返す")
    func noMigrationWhenNewKeyExists() {
        let item = item()
        var cache = [item.persistentKey: "new", "Movie.mp4": "legacy"]
        var persisted: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, cache: &cache) { persisted[$1] = $0 }

        #expect(key == item.persistentKey)
        #expect(cache[key] == "new")
        #expect(persisted.isEmpty, "移行が起きてはならない")
    }

    @Test("旧キーの値を新キーへ一度だけ移行し persist を呼ぶ")
    func migratesFromLegacyKey() {
        let item = item()
        var cache = ["Movie.mp4": "legacy"]
        var persisted: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, cache: &cache) { persisted[$1] = $0 }

        #expect(key == item.persistentKey)
        #expect(cache[key] == "legacy", "旧キーの値がキャッシュの新キーへコピーされる")
        #expect(persisted == [item.persistentKey: "legacy"], "新キーでストアへ書き込まれる")
        #expect(cache["Movie.mp4"] == "legacy", "旧キーのレコードは削除しない（現行挙動の踏襲）")
    }

    @Test("旧キーが複数一致しても最初の一致（タイトル優先）だけ移行する")
    func migratesFirstMatchOnly() {
        let item = item()
        var cache = ["Movie.mp4": "by-title", "obj-1": "by-id"]
        var persisted: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, cache: &cache) { persisted[$1] = $0 }

        #expect(cache[key] == "by-title")
        #expect(persisted == [item.persistentKey: "by-title"])
    }

    @Test("どこにも値が無ければ移行せず新キーだけ返す")
    func noValueAnywhere() {
        let item = item()
        var cache: [String: String] = [:]
        var persisted: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, cache: &cache) { persisted[$1] = $0 }

        #expect(key == item.persistentKey)
        #expect(cache.isEmpty)
        #expect(persisted.isEmpty)
    }

    @Test("尺・サイズが無い場合は新キー＝タイトルのみとなり legacy と衝突しても安全")
    func degeneratedKeyEqualsLegacyTitle() {
        // res に尺・サイズが無いと persistentKey はタイトルのみ = legacy と同じ値になる。
        let res = MediaResource(url: URL(string: "http://x/1")!)
        let item = MediaItem(id: "obj-1", parentID: "0", title: "Movie.mp4",
                             upnpClass: "object.item.videoItem", resources: [res])
        var cache = ["Movie.mp4": "value"]
        var persisted: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, cache: &cache) { persisted[$1] = $0 }

        #expect(key == "Movie.mp4")
        #expect(cache == ["Movie.mp4": "value"], "同一キーへの自己移行は起きない")
        #expect(persisted.isEmpty)
    }
}
