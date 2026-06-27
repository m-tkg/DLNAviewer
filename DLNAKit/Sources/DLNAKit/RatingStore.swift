import Foundation

/// 動画への評価。
public enum Rating: String, Codable, Sendable, CaseIterable {
    case none
    case like
    case dislike
}

/// 動画の評価を端末ローカルに永続化するストア。
///
/// キーは安定識別子（UPnP の object id 等）。`ManualServerStore` と同じ `KeyValueStorage`
/// を使う。
public final class RatingStore: @unchecked Sendable {
    private let storage: KeyValueStorage
    private let key: String
    private let lock = NSLock()

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "videoRatings") {
        self.storage = storage
        self.key = key
    }

    /// 指定 ID の評価（未設定なら `.none`）。
    public func rating(for id: String) -> Rating {
        lock.lock(); defer { lock.unlock() }
        return load()[id] ?? .none
    }

    /// 評価を設定する。`.none` の場合はレコードを削除する。
    public func setRating(_ rating: Rating, for id: String) {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        if rating == .none {
            dict[id] = nil
        } else {
            dict[id] = rating
        }
        save(dict)
    }

    /// 保存済みの全評価。
    public func all() -> [String: Rating] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    // MARK: - 内部

    private func load() -> [String: Rating] {
        guard let data = storage.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Rating].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ dict: [String: Rating]) {
        storage.set(try? JSONEncoder().encode(dict), forKey: key)
    }
}
