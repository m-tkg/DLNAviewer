import Foundation

/// 動画ごとのタグを端末ローカルに永続化するストア。
/// キーは安定識別子（UPnP の object id 等）。`RatingStore` と同じ `KeyValueStorage` を使う。
public final class TagStore: @unchecked Sendable {
    private let storage: KeyValueStorage
    private let key: String
    private let lock = NSLock()

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "videoTags") {
        self.storage = storage
        self.key = key
    }

    /// 指定 ID のタグ（昇順）。
    public func tags(for id: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return (load()[id] ?? []).sorted()
    }

    /// タグ一覧を設定する（空なら削除）。空文字・重複（大小無視）は除外。
    public func setTags(_ tags: [String], for id: String) {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        let clean = dedupe(tags)
        if clean.isEmpty {
            dict[id] = nil
        } else {
            dict[id] = clean
        }
        save(dict)
    }

    public func all() -> [String: [String]] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    /// 重複（大小無視）・空白を整理して昇順に。
    private func dedupe(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let lower = t.lowercased()
            if seen.insert(lower).inserted { result.append(t) }
        }
        return result.sorted()
    }

    // MARK: - 内部

    private func load() -> [String: [String]] {
        guard let data = storage.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ dict: [String: [String]]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        storage.set(data, forKey: key)
    }
}
