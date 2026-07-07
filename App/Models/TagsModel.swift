import Foundation
import Observation
import DLNAKit

/// 動画ごとのタグを保持・更新する。端末ローカル永続化＋iCloud 同期対象。
@MainActor
@Observable
final class TagsModel {
    static let shared = TagsModel()
    private let store: TagStore
    private let cache: PersistentValueCache<[String]>

    init(store: TagStore = TagStore()) {
        self.store = store
        self.cache = PersistentValueCache(cache: store.all()) { value, key in
            store.setTags(value ?? [], for: key)
        }
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache.reload(store.all())
    }

    func tags(for item: MediaItem) -> [String] {
        (cache.value(for: item) ?? []).sorted()
    }

    func add(_ tag: String, for item: MediaItem) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = cache.value(for: item) ?? []
        guard !list.contains(where: { $0.lowercased() == t.lowercased() }) else { return }
        list.append(t)
        cache.setValue(list.isEmpty ? nil : list.sorted(), for: item)
    }

    func remove(_ tag: String, for item: MediaItem) {
        var list = cache.value(for: item) ?? []
        list.removeAll { $0.lowercased() == tag.lowercased() }
        cache.setValue(list.isEmpty ? nil : list.sorted(), for: item)
    }

    /// すべての動画で使われているタグ（ユニーク・昇順）。自動補完用。
    func allTags() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for list in cache.cache.values {
            for tag in list where seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: グローバル操作（タグ管理）

    /// タグが使われている動画の本数。
    func usageCount(_ tag: String) -> Int {
        let lower = tag.lowercased()
        return cache.cache.values.filter { $0.contains { $0.lowercased() == lower } }.count
    }

    /// タグ名を一括変更（使っている全動画に反映、重複は統合）。
    func renameTag(_ old: String, to new: String) {
        let newName = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        let oldLower = old.lowercased()
        for (id, tags) in cache.cache where tags.contains(where: { $0.lowercased() == oldLower }) {
            var updated = tags.filter { $0.lowercased() != oldLower }
            if !updated.contains(where: { $0.lowercased() == newName.lowercased() }) {
                updated.append(newName)
            }
            cache.set(updated.isEmpty ? nil : updated.sorted(), forKey: id)
        }
    }

    /// タグを一括削除（使っている全動画から外す）。
    func deleteTag(_ tag: String) {
        let lower = tag.lowercased()
        for (id, tags) in cache.cache where tags.contains(where: { $0.lowercased() == lower }) {
            let updated = tags.filter { $0.lowercased() != lower }
            cache.set(updated.isEmpty ? nil : updated.sorted(), forKey: id)
        }
    }
}
