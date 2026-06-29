import Foundation
import Testing
@testable import DLNAKit

@Suite("FavoriteFolderStore")
struct FavoriteFolderStoreTests {
    private func makeServer(id: String = "udn:1") -> MediaServer {
        MediaServer(
            id: id,
            friendlyName: "NAS",
            descriptionURL: URL(string: "http://192.168.1.10:8200/rootDesc.xml")!,
            origin: .discovered
        )
    }

    @Test("追加したお気に入りが取得できる")
    func addAndList() {
        let store = FavoriteFolderStore(storage: MemoryStorage(), key: "test")
        store.add(server: makeServer(), objectID: "64", title: "映画")

        let folders = store.folders()
        #expect(folders.count == 1)
        #expect(folders[0].objectID == "64")
        #expect(folders[0].title == "映画")
        #expect(folders[0].server.id == "udn:1")
    }

    @Test("同一サーバー・同一フォルダ（同じ objectID・同じ名前）は重複追加されない")
    func deduplicates() {
        let store = FavoriteFolderStore(storage: MemoryStorage(), key: "test")
        let a = store.add(server: makeServer(), objectID: "64", title: "映画")
        let b = store.add(server: makeServer(), objectID: "64", title: "映画")
        #expect(store.folders().count == 1)
        #expect(a.id == b.id)
    }

    @Test("サーバーが違えば別物として追加される")
    func differentServers() {
        let store = FavoriteFolderStore(storage: MemoryStorage(), key: "test")
        store.add(server: makeServer(id: "udn:1"), objectID: "64", title: "映画")
        store.add(server: makeServer(id: "udn:2"), objectID: "64", title: "映画")
        #expect(store.folders().count == 2)
    }

    @Test("contains で登録済みか判定できる")
    func contains() {
        let store = FavoriteFolderStore(storage: MemoryStorage(), key: "test")
        store.add(server: makeServer(), objectID: "64", title: "映画")
        #expect(store.contains(serverID: "udn:1", objectID: "64", title: "映画"))
        #expect(!store.contains(serverID: "udn:1", objectID: "99", title: "映画"))
    }

    @Test("同じ objectID でも名前が違えば別物として扱う（再利用フォルダへの誤マーク防止）")
    func sameObjectIDDifferentTitle() {
        let store = FavoriteFolderStore(storage: MemoryStorage(), key: "test")
        store.add(server: makeServer(), objectID: "64", title: "映画")
        #expect(store.contains(serverID: "udn:1", objectID: "64", title: "映画"))
        #expect(!store.contains(serverID: "udn:1", objectID: "64", title: "別フォルダ"))
    }

    @Test("削除できる")
    func remove() {
        let store = FavoriteFolderStore(storage: MemoryStorage(), key: "test")
        let entry = store.add(server: makeServer(), objectID: "64", title: "映画")
        store.add(server: makeServer(), objectID: "65", title: "ドラマ")
        store.remove(id: entry.id)

        let folders = store.folders()
        #expect(folders.count == 1)
        #expect(folders.first?.objectID == "65")
    }

    @Test("toggle で追加・解除が切り替わる")
    func toggle() {
        let store = FavoriteFolderStore(storage: MemoryStorage(), key: "test")
        let added = store.toggle(server: makeServer(), objectID: "64", title: "映画")
        #expect(added)
        #expect(store.contains(serverID: "udn:1", objectID: "64", title: "映画"))

        let removed = store.toggle(server: makeServer(), objectID: "64", title: "映画")
        #expect(!removed)
        #expect(!store.contains(serverID: "udn:1", objectID: "64", title: "映画"))
    }

    @Test("別インスタンスでも永続化が共有される")
    func persistsAcrossInstances() {
        let storage = MemoryStorage()
        let store1 = FavoriteFolderStore(storage: storage, key: "test")
        store1.add(server: makeServer(), objectID: "64", title: "映画")

        let store2 = FavoriteFolderStore(storage: storage, key: "test")
        #expect(store2.folders().count == 1)
    }
}
