import Foundation
import Testing
import DLNAKit
@testable import DLNAviewer

private func makeDiscoveredServer(
    id: String = "uuid:test",
    name: String = "NAS",
    descriptionURL: URL = URL(string: "http://nas/desc.xml")!
) -> MediaServer {
    MediaServer(id: id, friendlyName: name, descriptionURL: descriptionURL,
                contentDirectoryControlURL: URL(string: "http://nas/control")!,
                origin: .discovered)
}

@MainActor
@Suite("LibraryModel")
struct LibraryModelTests {
    @Test("発見済みサーバーを保存すると登録済み一覧に加わり、発見済みからは消える")
    func savesDiscoveredServer() {
        let model = LibraryModel(store: ManualServerStore(storage: InMemoryStorage()))
        let server = makeDiscoveredServer()
        model.discovered = [server]

        model.saveDiscoveredServer(server)

        #expect(model.discovered.isEmpty)
        #expect(model.servers.map(\.displayName) == ["NAS"])
    }

    @Test("保存した内容は ManualServerStore に永続化される")
    func persistsToStore() {
        let store = ManualServerStore(storage: InMemoryStorage())
        let model = LibraryModel(store: store)
        let server = makeDiscoveredServer()

        model.saveDiscoveredServer(server)

        let entries = store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.descriptionURL == server.descriptionURL)
        #expect(entries.first?.name == "NAS")
    }
}
