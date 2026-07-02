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
    /// ユーザーが付けた表示名。`nil` のときは `title`（フォルダ実名）を表示する。
    /// `id` の計算には含めないため、改名しても同じフォルダを指す ID は変わらない。
    public var displayName: String?

    public init(server: MediaServer, objectID: String, title: String, path: [String] = [], displayName: String? = nil) {
        self.id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID, title: title)
        self.server = server
        self.objectID = objectID
        self.title = title
        self.path = path
        self.displayName = displayName
    }

    /// サーバー ID・フォルダ ID・フォルダ名から一意キーを作る。
    /// title を含めることで、サーバー入れ替えで objectID が別フォルダに再利用されても
    /// 名前が違えば別物として扱える（誤ってお気に入りマークが付くのを防ぐ）。
    public static func makeID(serverID: String, objectID: String, title: String) -> String {
        "\(serverID)\u{1}\(objectID)\u{1}\(title)"
    }

    private enum CodingKeys: String, CodingKey { case id, server, objectID, title, path, displayName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decode(MediaServer.self, forKey: .server)
        objectID = try c.decode(String.self, forKey: .objectID)
        title = try c.decode(String.self, forKey: .title)
        path = try c.decodeIfPresent([String].self, forKey: .path) ?? []   // 旧データ互換
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)   // 旧データは nil
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
        try c.encodeIfPresent(displayName, forKey: .displayName)
    }
}

/// お気に入りフォルダの一覧を永続化するストア。
public final class FavoriteFolderStore: @unchecked Sendable {
    private let core: JSONStoreCore<[FavoriteFolder]>

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "favoriteFolders") {
        core = JSONStoreCore(storage: storage, key: key, default: { [] })
    }

    /// 登録済みお気に入り一覧（登録順）。
    public func folders() -> [FavoriteFolder] {
        core.read { $0 }
    }

    /// お気に入りを追加する。同一サーバー・同一フォルダが既にあれば重複追加しない。
    @discardableResult
    public func add(server: MediaServer, objectID: String, title: String, path: [String] = []) -> FavoriteFolder {
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID, title: title)
        return core.mutate { list in
            if let existing = list.first(where: { $0.id == id }) {
                return existing
            }
            let entry = FavoriteFolder(server: server, objectID: objectID, title: title, path: path)
            list.append(entry)
            return entry
        }
    }

    /// 指定 ID のお気に入りを削除する。
    public func remove(id: String) {
        core.mutate { list in
            list.removeAll { $0.id == id }
        }
    }

    /// 指定 ID のお気に入りに表示名を付ける。空文字（または空白のみ）なら `nil` に戻し、
    /// フォルダ実名（`title`）表示へ戻す。
    public func rename(id: String, to displayName: String) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        core.mutate { list in
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
            list[idx].displayName = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// 並べ替え（SwiftUI の `onMove` から渡る `IndexSet`/挿入先をそのまま適用）。
    /// DLNAKit は SwiftUI 非依存のため、`Array.move(fromOffsets:toOffset:)` 相当を自前実装する。
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        core.mutate { list in
            let moving = source.sorted().map { list[$0] }
            // 後ろの要素から削除してインデックスのずれを防ぐ。
            for i in source.sorted(by: >) { list.remove(at: i) }
            // 削除で前方が詰まった分、挿入位置を補正する。
            let insertAt = destination - source.filter { $0 < destination }.count
            list.insert(contentsOf: moving, at: insertAt)
        }
    }

    /// 指定サーバー・フォルダが登録済みか。
    public func contains(serverID: String, objectID: String, title: String) -> Bool {
        let id = FavoriteFolder.makeID(serverID: serverID, objectID: objectID, title: title)
        return core.read { list in
            list.contains { $0.id == id }
        }
    }

    /// 登録/解除を切り替える。
    /// - Returns: 切り替え後に登録されていれば `true`、解除されていれば `false`。
    @discardableResult
    public func toggle(server: MediaServer, objectID: String, title: String, path: [String] = []) -> Bool {
        let id = FavoriteFolder.makeID(serverID: server.id, objectID: objectID, title: title)
        return core.mutate { list in
            if list.contains(where: { $0.id == id }) {
                list.removeAll { $0.id == id }
                return false
            } else {
                list.append(FavoriteFolder(server: server, objectID: objectID, title: title, path: path))
                return true
            }
        }
    }
}
