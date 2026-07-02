import Foundation
import Observation
import DLNAKit

/// 動画ごとのブックマーク（再生位置）を保持・更新する。端末ローカル永続化。
@MainActor
@Observable
final class BookmarksModel {
    static let shared = BookmarksModel()

    private var cache: [String: [Double]]
    private let store: BookmarkStore

    init(store: BookmarkStore = BookmarkStore()) {
        self.store = store
        self.cache = store.all()
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache = store.all()
    }

    func bookmarks(for item: MediaItem) -> [Double] {
        (cache[key(for: item)] ?? []).sorted()
    }

    /// 現在位置を追加（約0.4秒以内の近接重複のみ無視）。
    func add(_ time: Double, for item: MediaItem) {
        guard time.isFinite, time >= 0 else { return }
        let k = key(for: item)
        var list = cache[k] ?? []
        guard !list.contains(where: { abs($0 - time) < 0.4 }) else { return }
        list.append(time)
        list.sort()
        cache[k] = list
        store.setBookmarks(list, for: k)
    }

    func remove(_ time: Double, for item: MediaItem) {
        let k = key(for: item)
        var list = cache[k] ?? []
        list.removeAll { abs($0 - time) < 0.001 }
        cache[k] = list.isEmpty ? nil : list
        store.setBookmarks(list, for: k)
    }

    /// 同一性キー。旧スキーム（タイトルのみ／object id）のデータが残っていれば一度だけ移行する。
    private func key(for item: MediaItem) -> String {
        PersistentKeyMigration.key(for: item, cache: &cache) { store.setBookmarks($0, for: $1) }
    }
}
