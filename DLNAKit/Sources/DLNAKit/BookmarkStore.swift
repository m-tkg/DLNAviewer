import Foundation

/// 動画ごとのブックマーク（再生位置・秒）を端末ローカルに永続化するストア。
/// キーは安定識別子（UPnP の object id 等）。`RatingStore` と同じ `KeyValueStorage` を使う。
public final class BookmarkStore: @unchecked Sendable {
    private let storage: KeyValueStorage
    private let key: String
    private let lock = NSLock()

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "videoBookmarks") {
        self.storage = storage
        self.key = key
    }

    /// 指定 ID のブックマーク（昇順）。
    public func bookmarks(for id: String) -> [Double] {
        lock.lock(); defer { lock.unlock() }
        return (load()[id] ?? []).sorted()
    }

    /// ブックマーク一覧を設定する（空なら削除）。非有限値は除外する。
    public func setBookmarks(_ times: [Double], for id: String) {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        let clean = times.filter { $0.isFinite }.sorted()
        if clean.isEmpty {
            dict[id] = nil
        } else {
            dict[id] = clean
        }
        save(dict)
    }

    public func all() -> [String: [Double]] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    // MARK: - 内部

    private func load() -> [String: [Double]] {
        guard let data = storage.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [Double]].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ dict: [String: [Double]]) {
        // エンコード失敗時は既存データを消さない（nil で上書きしない）。
        guard let data = try? JSONEncoder().encode(dict) else { return }
        storage.set(data, forKey: key)
    }
}
