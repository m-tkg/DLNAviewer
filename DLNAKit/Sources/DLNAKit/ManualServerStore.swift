import Foundation

/// 手動登録したサーバー 1 件（記述 URL ＋任意の表示名）。
public struct ManualServerEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var descriptionURL: URL
    public var name: String?

    public init(id: UUID = UUID(), descriptionURL: URL, name: String? = nil) {
        self.id = id
        self.descriptionURL = descriptionURL
        self.name = name
    }
}

/// `ManualServerStore` の永続化バックエンド（テスト時に差し替え可能）。
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

/// 手動登録サーバーの一覧を永続化するストア。
public final class ManualServerStore: @unchecked Sendable {
    private let storage: KeyValueStorage
    private let key: String
    private let lock = NSLock()

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "manualServers") {
        self.storage = storage
        self.key = key
    }

    /// 登録済みエントリ一覧（登録順）。
    public func entries() -> [ManualServerEntry] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    /// 記述 URL を追加する。同一 URL が既にあれば重複追加しない。
    /// - Returns: 追加（または既存）エントリ。
    @discardableResult
    public func add(descriptionURL: URL, name: String? = nil) -> ManualServerEntry {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        if let existing = list.first(where: { $0.descriptionURL == descriptionURL }) {
            return existing
        }
        let entry = ManualServerEntry(descriptionURL: descriptionURL, name: name)
        list.append(entry)
        save(list)
        return entry
    }

    /// 指定 ID のエントリを削除する。
    public func remove(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }

    // MARK: - 内部

    private func load() -> [ManualServerEntry] {
        guard let data = storage.data(forKey: key),
              let list = try? JSONDecoder().decode([ManualServerEntry].self, from: data) else {
            return []
        }
        return list
    }

    private func save(_ list: [ManualServerEntry]) {
        let data = try? JSONEncoder().encode(list)
        storage.set(data, forKey: key)
    }
}
