import Foundation
import Observation
import DLNAKit

/// お気に入りフォルダを保持・更新する。端末ローカル永続化＋iCloud 同期対象。
@MainActor
@Observable
final class FavoritesModel {
    static let shared = FavoritesModel()

    private(set) var folders: [FavoriteFolder]
    private let store: FavoriteFolderStore

    init(store: FavoriteFolderStore = FavoriteFolderStore()) {
        self.store = store
        self.folders = store.folders()
    }

    /// ストアから読み直す（iCloud 同期反映用）。
    func reload() {
        folders = store.folders()
    }

    func contains(serverID: String, objectID: String) -> Bool {
        store.contains(serverID: serverID, objectID: objectID)
    }

    /// 登録/解除を切り替える。
    @discardableResult
    func toggle(server: MediaServer, objectID: String, title: String) -> Bool {
        let added = store.toggle(server: server, objectID: objectID, title: title)
        folders = store.folders()
        return added
    }

    func remove(id: String) {
        store.remove(id: id)
        folders = store.folders()
    }
}
