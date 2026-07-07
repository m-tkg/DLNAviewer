import Foundation
import Observation
import DLNAKit

/// 動画ごとのブックマーク（再生位置）を保持・更新する。端末ローカル永続化。
@MainActor
@Observable
final class BookmarksModel {
    static let shared = BookmarksModel()
    private let store: BookmarkStore
    private let cache: PersistentValueCache<[Double]>

    init(store: BookmarkStore = BookmarkStore()) {
        self.store = store
        self.cache = PersistentValueCache(cache: store.all()) { value, key in
            store.setBookmarks(value ?? [], for: key)
        }
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache.reload(store.all())
    }

    func bookmarks(for item: MediaItem) -> [Double] {
        (cache.value(for: item) ?? []).sorted()
    }

    /// 現在位置を追加（約0.4秒以内の近接重複のみ無視）。
    func add(_ time: Double, for item: MediaItem) {
        guard time.isFinite, time >= 0 else { return }
        var list = cache.value(for: item) ?? []
        guard !list.contains(where: { abs($0 - time) < 0.4 }) else { return }
        list.append(time)
        list.sort()
        cache.setValue(list, for: item)
    }

    func remove(_ time: Double, for item: MediaItem) {
        var list = cache.value(for: item) ?? []
        list.removeAll { abs($0 - time) < 0.001 }
        cache.setValue(list.isEmpty ? nil : list, for: item)
    }
}
