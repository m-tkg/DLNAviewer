import Foundation

/// お気に入り登録したフォルダ 1 件（サーバーごと保持し、そのまま再ブラウズできる）。
public struct FavoriteFolder: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var server: MediaServer
    public var objectID: String
    public var title: String
    /// ルート直下からこのフォルダまでのフォルダ名の連なり（サーバー入れ替え時の objectID 再解決用）。
    /// 旧データには無いため、空のときは再解決せず objectID をそのまま使う。
    public var path: [String]

    public init(server: MediaServer, objectID: String, title: String, path: [String] = []) {
        self.id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID, title: title)
        self.server = server
        self.objectID = objectID
        self.title = title
        self.path = path
    }

    /// サーバー ID・フォルダ ID・フォルダ名から一意キーを作る。
    /// title を含めることで、サーバー入れ替えで objectID が別フォルダに再利用されても
    /// 名前が違えば別物として扱える（誤ってお気に入りマークが付くのを防ぐ）。
    public static func makeID(serverID: String, objectID: String, title: String) -> String {
        "\(serverID)\u{1}\(objectID)\u{1}\(title)"
    }

    private enum CodingKeys: String, CodingKey { case id, server, objectID, title, path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decode(MediaServer.self, forKey: .server)
        objectID = try c.decode(String.self, forKey: .objectID)
        title = try c.decode(String.self, forKey: .title)
        path = try c.decodeIfPresent([String].self, forKey: .path) ?? []   // 旧データ互換
        // id は objectID+title から再計算する（旧データの objectID のみの id を移行）。
        id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID, title: title)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(server, forKey: .server)
        try c.encode(objectID, forKey: .objectID)
        try c.encode(title, forKey: .title)
        try c.encode(path, forKey: .path)
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
    public func add(server: MediaServer, objectID: String, title: String, path: [String] = []) -> FavoriteFolder {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID, title: title)
        if let existing = list.first(where: { $0.id == id }) {
            return existing
        }
        let entry = FavoriteFolder(server: server, objectID: objectID, title: title, path: path)
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
    public func contains(serverID: String, objectID: String, title: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let id = FavoriteFolder.makeID(serverID: serverID, objectID: objectID, title: title)
        return load().contains { $0.id == id }
    }

    /// 登録/解除を切り替える。
    /// - Returns: 切り替え後に登録されていれば `true`、解除されていれば `false`。
    @discardableResult
    public func toggle(server: MediaServer, objectID: String, title: String, path: [String] = []) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var list = load()
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID, title: title)
        if list.contains(where: { $0.id == id }) {
            list.removeAll { $0.id == id }
            save(list)
            return false
        } else {
            list.append(FavoriteFolder(server: server, objectID: objectID, title: title, path: path))
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
