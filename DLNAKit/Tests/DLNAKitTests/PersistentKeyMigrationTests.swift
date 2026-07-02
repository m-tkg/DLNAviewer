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
        let cache = [item.persistentKey: "new", "Movie.mp4": "legacy"]
        var migrated: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, lookup: { cache[$0] }) { migrated[$1] = $0 }

        #expect(key == item.persistentKey)
        #expect(migrated.isEmpty, "移行が起きてはならない")
    }

    @Test("旧キーの値を新キーへ一度だけ移行する（migrate に値と新キーが渡る）")
    func migratesFromLegacyKey() {
        let item = item()
        let cache = ["Movie.mp4": "legacy"]
        var migrated: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, lookup: { cache[$0] }) { migrated[$1] = $0 }

        #expect(key == item.persistentKey)
        #expect(migrated == [item.persistentKey: "legacy"], "旧キーの値が新キーで migrate に渡される")
    }

    @Test("旧キーが複数一致しても最初の一致（タイトル優先）だけ移行する")
    func migratesFirstMatchOnly() {
        let item = item()
        let cache = ["Movie.mp4": "by-title", "obj-1": "by-id"]
        var migrated: [String: String] = [:]

        _ = PersistentKeyMigration.key(for: item, lookup: { cache[$0] }) { migrated[$1] = $0 }

        #expect(migrated == [item.persistentKey: "by-title"])
    }

    @Test("どこにも値が無ければ移行せず新キーだけ返す（migrate は呼ばれない）")
    func noValueAnywhere() {
        let item = item()
        let cache: [String: String] = [:]
        var migrated: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, lookup: { cache[$0] }) { migrated[$1] = $0 }

        #expect(key == item.persistentKey)
        #expect(migrated.isEmpty)
    }

    @Test("尺・サイズが無い場合は新キー＝タイトルのみとなり legacy と衝突しても安全")
    func degeneratedKeyEqualsLegacyTitle() {
        // res に尺・サイズが無いと persistentKey はタイトルのみ = legacy と同じ値になる。
        let res = MediaResource(url: URL(string: "http://x/1")!)
        let item = MediaItem(id: "obj-1", parentID: "0", title: "Movie.mp4",
                             upnpClass: "object.item.videoItem", resources: [res])
        let cache = ["Movie.mp4": "value"]
        var migrated: [String: String] = [:]

        let key = PersistentKeyMigration.key(for: item, lookup: { cache[$0] }) { migrated[$1] = $0 }

        #expect(key == "Movie.mp4")
        #expect(migrated.isEmpty, "同一キーへの自己移行は起きない")
    }

    @Test("参照だけでは lookup 以外のクロージャが呼ばれない（読み取りは書き込みを伴わない）")
    func lookupOnlyOnReadPath() {
        let item = item()
        var lookupCount = 0
        var migrateCount = 0

        // 値が既にある場合: 新キーの lookup 1 回だけで返る。
        _ = PersistentKeyMigration.key(for: item, lookup: { key -> String? in
            lookupCount += 1
            return key == item.persistentKey ? "new" : nil
        }) { _, _ in migrateCount += 1 }
        #expect(lookupCount == 1)
        #expect(migrateCount == 0)

        // 値がどこにも無い場合: legacy を全部探すが migrate は呼ばれない。
        lookupCount = 0
        _ = PersistentKeyMigration.key(for: item, lookup: { _ -> String? in
            lookupCount += 1
            return nil
        }) { _, _ in migrateCount += 1 }
        #expect(lookupCount == 1 + item.legacyPersistentKeys.filter { $0 != item.persistentKey }.count)
        #expect(migrateCount == 0)
    }
}
