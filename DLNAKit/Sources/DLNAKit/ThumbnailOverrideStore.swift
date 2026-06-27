import Foundation

/// 動画ごとの「サムネイルに使うシーンの時刻（秒）」を端末ローカルに永続化するストア。
/// キーは安定識別子（UPnP の object id 等）。`RatingStore` と同じ `KeyValueStorage` を使う。
public final class ThumbnailOverrideStore: @unchecked Sendable {
    private let storage: KeyValueStorage
    private let key: String
    private let lock = NSLock()

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "thumbnailOverrides") {
        self.storage = storage
        self.key = key
    }

    /// 指定 ID のサムネイル時刻（未設定なら nil）。
    public func time(for id: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        return load()[id]
    }

    /// サムネイル時刻を設定する（nil で削除）。非有限値は無視。
    public func setTime(_ time: Double?, for id: String) {
        lock.lock(); defer { lock.unlock() }
        var dict = load()
        if let time, time.isFinite, time >= 0 {
            dict[id] = time
        } else {
            dict[id] = nil
        }
        save(dict)
    }

    public func all() -> [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    // MARK: - 内部

    private func load() -> [String: Double] {
        guard let data = storage.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ dict: [String: Double]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        storage.set(data, forKey: key)
    }
}
