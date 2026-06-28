import Foundation

/// お気に入り登録したフォルダ 1 件（サーバーごと保持し、そのまま再ブラウズできる）。
public struct FavoriteFolder: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var server: MediaServer
    public var objectID: String
    public var title: String

    public init(server: MediaServer, objectID: String, title: String) {
        self.id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID)
        self.server = server
        self.objectID = objectID
        self.title = title
    }

    /// サーバー ID とフォルダ ID から安定した一意キーを作る。
    public static func makeID(serverID: String, objectID: String) -> String {
        "\(serverID)\u{1}\(objectID)"
    }
}

/// お気に入りフォルダの一覧を永続化するストア。
public final class FavoriteFolderStore: @unchecked Sendable {
    private let storage: KeyValueStorage
    private let key: String
    private let lock = NSLock()

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "favoriteFolders") {
        self.storage = storage
        self.key = key
    }

    /// 登録済みお気に入り一覧（登録順）。
    public func folders() -> [FavoriteFolder] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    /// お気に入りを追加する。同一サーバー・同一フォルダが既にあれば重複追加しない。
    @discardableResult
    public func add(server: MediaServer, objectID: String, title: String) -> FavoriteFolder {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID)
        if let existing = list.first(where: { $0.id == id }) {
            return existing
        }
        let entry = FavoriteFolder(server: server, objectID: objectID, title: title)
        list.append(entry)
        save(list)
        return entry
    }

    /// 指定 ID のお気に入りを削除する。
    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }

    /// 指定サーバー・フォルダが登録済みか。
    public func contains(serverID: String, objectID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let id = FavoriteFolder.makeID(serverID: serverID, objectID: objectID)
        return load().contains { $0.id == id }
    }

    /// 登録/解除を切り替える。
    /// - Returns: 切り替え後に登録されていれば `true`、解除されていれば `false`。
    @discardableResult
    public func toggle(server: MediaServer, objectID: String, title: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID)
        if list.contains(where: { $0.id == id }) {
            list.removeAll { $0.id == id }
            save(list)
            return false
        } else {
            list.append(FavoriteFolder(server: server, objectID: objectID, title: title))
            save(list)
            return true
        }
    }

    // MARK: - 内部

    private func load() -> [FavoriteFolder] {
        guard let data = storage.data(forKey: key),
              let list = try? JSONDecoder().decode([FavoriteFolder].self, from: data) else {
            return []
        }
        return list
    }

    private func save(_ list: [FavoriteFolder]) {
        let data = try? JSONEncoder().encode(list)
        storage.set(data, forKey: key)
    }
}
