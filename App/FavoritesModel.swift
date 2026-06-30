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

    func contains(serverID: String, objectID: String, title: String) -> Bool {
        store.contains(serverID: serverID, objectID: objectID, title: title)
    }

    /// 登録/解除を切り替える。
    @discardableResult
    func toggle(server: MediaServer, objectID: String, title: String, path: [String] = []) -> Bool {
        let added = store.toggle(server: server, objectID: objectID, title: title, path: path)
        folders = store.folders()
        return added
    }

    func remove(id: String) {
        store.remove(id: id)
        folders = store.folders()
    }

    /// 表示名を変更する（空文字ならフォルダ実名へ戻す）。
    func rename(id: String, to displayName: String) {
        store.rename(id: id, to: displayName)
        folders = store.folders()
    }

    /// 並べ替え（SwiftUI の `onMove` から呼ぶ）。
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
        folders = store.folders()
    }
}
