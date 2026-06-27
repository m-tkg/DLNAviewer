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

    @Test("別インスタンスでも永続化が共有される")
    func persistsAcrossInstances() {
        let storage = MemoryStorage()
        let store1 = ManualServerStore(storage: storage, key: "test")
        store1.add(descriptionURL: URL(string: "http://h/d.xml")!)

        let store2 = ManualServerStore(storage: storage, key: "test")
        #expect(store2.entries().count == 1)
    }
}
