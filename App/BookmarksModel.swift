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

    func bookmarks(for item: MediaItem) -> [Double] {
        (cache[item.id] ?? []).sorted()
    }

    /// 現在位置を追加（約0.4秒以内の近接重複のみ無視）。
    func add(_ time: Double, for item: MediaItem) {
        guard time.isFinite, time >= 0 else { return }
        var list = cache[item.id] ?? []
        guard !list.contains(where: { abs($0 - time) < 0.4 }) else { return }
        list.append(time)
        list.sort()
        cache[item.id] = list
        store.setBookmarks(list, for: item.id)
    }

    func remove(_ time: Double, for item: MediaItem) {
        var list = cache[item.id] ?? []
        list.removeAll { abs($0 - time) < 0.001 }
        cache[item.id] = list.isEmpty ? nil : list
        store.setBookmarks(list, for: item.id)
    }
}
