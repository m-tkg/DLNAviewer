import Foundation
import Testing
@testable import DLNAKit

/// テスト用のインメモリ永続化。
final class MemoryStorage: KeyValueStorage, @unchecked Sendable {
    private var dict: [String: Data] = [:]
    func data(forKey key: String) -> Data? { dict[key] }
    func set(_ data: Data?, forKey key: String) { dict[key] = data }
}

@Suite("ManualServerStore")
struct ManualServerStoreTests {
    @Test("追加したエントリが取得できる")
    func addAndList() {
        let store = ManualServerStore(storage: MemoryStorage(), key: "test")
        let url = URL(string: "http://192.168.1.10:8200/rootDesc.xml")!
        store.add(descriptionURL: url, name: "NAS")

        let entries = store.entries()
        #expect(entries.count == 1)
        #expect(entries[0].descriptionURL == url)
        #expect(entries[0].name == "NAS")
    }

    @Test("同一 URL は重複追加されない")
    func deduplicates() {
        let store = ManualServerStore(storage: MemoryStorage(), key: "test")
        let url = URL(string: "http://h:8200/d.xml")!
        let a = store.add(descriptionURL: url)
        let b = store.add(descriptionURL: url)
        #expect(store.entries().count == 1)
        #expect(a.id == b.id)
    }

    @Test("削除できる")
    func remove() {
        let store = ManualServerStore(storage: MemoryStorage(), key: "test")
        let entry = store.add(descriptionURL: URL(string: "http://h/d.xml")!)
        store.add(descriptionURL: URL(string: "http://h2/d.xml")!)
        store.remove(id: entry.id)

        let entries = store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.descriptionURL == URL(string: "http://h2/d.xml"))
    }

    @Test("URL と名前を更新できる（id と並び順は維持）")
    func update() {
        let store = ManualServerStore(storage: MemoryStorage(), key: "test")
        let first = store.add(descriptionURL: URL(string: "http://h1/d.xml")!, name: "A")
        let second = store.add(descriptionURL: URL(string: "http://h2/d.xml")!, name: "B")

        let updated = store.update(
            id: first.id,
            descriptionURL: URL(string: "http://192.168.1.20:9000/desc.xml")!,
            name: "NAS"
        )
        #expect(updated?.id == first.id)

        let entries = store.entries()
        #expect(entries.count == 2)
        #expect(entries[0].id == first.id)   // 並び順維持
        #expect(entries[0].descriptionURL == URL(string: "http://192.168.1.20:9000/desc.xml"))
        #expect(entries[0].name == "NAS")
        #expect(entries[1].id == second.id)  // 他は不変
        #expect(entries[1].descriptionURL == URL(string: "http://h2/d.xml"))
    }

    @Test("存在しない id の更新は nil を返し何も変えない")
    func updateMissing() {
        let store = ManualServerStore(storage: MemoryStorage(), key: "test")
        store.add(descriptionURL: URL(string: "http://h1/d.xml")!)
        let result = store.update(id: UUID(), descriptionURL: URL(string: "http://x/y.xml")!, name: nil)
        #expect(result == nil)
        #expect(store.entries().count == 1)
        #expect(store.entries()[0].descriptionURL == URL(string: "http://h1/d.xml"))
    }

    @Test("別インスタンスでも永続化が共有される")
    func persistsAcrossInstances() {
        let storage = MemoryStorage()
        let store1 = ManualServerStore(storage: storage, key: "test")
        store1.add(descriptionURL: URL(string: "http://h/d.xml")!)

        let store2 = ManualServerStore(storage: storage, key: "test")
        #expect(store2.entries().count == 1)
    }
}
