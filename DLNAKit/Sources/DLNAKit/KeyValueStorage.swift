import Foundation

/// 永続化ストア群の共通バックエンド（テスト時に差し替え可能）。
public protocol KeyValueStorage: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

extension UserDefaults: @retroactive @unchecked Sendable {}
extension UserDefaults: KeyValueStorage {
    public func data(forKey key: String) -> Data? {
        object(forKey: key) as? Data
    }
    public func set(_ data: Data?, forKey key: String) {
        setValue(data, forKey: key)
    }
}

/// インメモリの `KeyValueStorage`。ユニットテストや SwiftUI プレビューで使う。
public final class InMemoryStorage: KeyValueStorage, @unchecked Sendable {
    private var dict: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return dict[key]
    }
    public func set(_ data: Data?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        dict[key] = data
    }
}
