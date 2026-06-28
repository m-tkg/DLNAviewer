import Foundation
import Observation
import DLNAKit

/// 動画ごとのタグを保持・更新する。端末ローカル永続化＋iCloud 同期対象。
@MainActor
@Observable
final class TagsModel {
    static let shared = TagsModel()

    private var cache: [String: [String]]
    private let store: TagStore

    init(store: TagStore = TagStore()) {
        self.store = store
        self.cache = store.all()
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache = store.all()
    }

    func tags(for item: MediaItem) -> [String] {
        (cache[key(for: item)] ?? []).sorted()
    }

    func add(_ tag: String, for item: MediaItem) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = cache[key(for: item)] ?? []
        guard !list.contains(where: { $0.lowercased() == t.lowercased() }) else { return }
        list.append(t)
        commit(list, for: item)
    }

    func remove(_ tag: String, for item: MediaItem) {
        var list = cache[key(for: item)] ?? []
        list.removeAll { $0.lowercased() == tag.lowercased() }
        commit(list, for: item)
    }

    /// 同一性キー。旧スキーム（タイトルのみ／object id）のデータが残っていれば一度だけ移行する。
    private func key(for item: MediaItem) -> String {
        let key = item.persistentKey
        guard cache[key] == nil else { return key }
        for legacy in item.legacyPersistentKeys where legacy != key {
            if let value = cache[legacy] {
                cache[key] = value
                store.setTags(value, for: key)
                break
            }
        }
        return key
    }

    /// すべての動画で使われているタグ（ユニーク・昇順）。自動補完用。
    func allTags() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for list in cache.values {
            for tag in list where seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func commit(_ list: [String], for item: MediaItem) {
        let k = key(for: item)
        cache[k] = list.isEmpty ? nil : list.sorted()
        store.setTags(list, for: k)
    }

    // MARK: グローバル操作（タグ管理）

    /// タグが使われている動画の本数。
    func usageCount(_ tag: String) -> Int {
        let lower = tag.lowercased()
        return cache.values.filter { $0.contains { $0.lowercased() == lower } }.count
    }

    /// タグ名を一括変更（使っている全動画に反映、重複は統合）。
    func renameTag(_ old: String, to new: String) {
        let newName = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        let oldLower = old.lowercased()
        for (id, tags) in cache where tags.contains(where: { $0.lowercased() == oldLower }) {
            var updated = tags.filter { $0.lowercased() != oldLower }
            if !updated.contains(where: { $0.lowercased() == newName.lowercased() }) {
                updated.append(newName)
            }
            cache[id] = updated.isEmpty ? nil : updated.sorted()
            store.setTags(updated, for: id)
        }
    }

    /// タグを一括削除（使っている全動画から外す）。
    func deleteTag(_ tag: String) {
        let lower = tag.lowercased()
        for (id, tags) in cache where tags.contains(where: { $0.lowercased() == lower }) {
            let updated = tags.filter { $0.lowercased() != lower }
            cache[id] = updated.isEmpty ? nil : updated.sorted()
            store.setTags(updated, for: id)
        }
    }
}
