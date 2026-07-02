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

/// 手動登録サーバーの一覧を永続化するストア。
public final class ManualServerStore: @unchecked Sendable {
    private let core: JSONStoreCore<[ManualServerEntry]>

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "manualServers") {
        core = JSONStoreCore(storage: storage, key: key, default: { [] })
    }

    /// 登録済みエントリ一覧（登録順）。
    public func entries() -> [ManualServerEntry] {
        core.read { $0 }
    }

    /// 記述 URL を追加する。同一 URL が既にあれば重複追加しない。
    /// - Returns: 追加（または既存）エントリ。
    @discardableResult
    public func add(descriptionURL: URL, name: String? = nil) -> ManualServerEntry {
        core.mutate { list in
            if let existing = list.first(where: { $0.descriptionURL == descriptionURL }) {
                return existing
            }
            let entry = ManualServerEntry(descriptionURL: descriptionURL, name: name)
            list.append(entry)
            return entry
        }
    }

    /// 指定 ID のエントリの記述 URL と名前を更新する（id と並び順は維持）。
    /// - Returns: 更新後のエントリ。該当 ID が無ければ nil。
    @discardableResult
    public func update(id: UUID, descriptionURL: URL, name: String?) -> ManualServerEntry? {
        core.mutate { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
            list[index].descriptionURL = descriptionURL
            list[index].name = name
            return list[index]
        }
    }

    /// 指定 ID のエントリを削除する。
    public func remove(id: UUID) {
        core.mutate { list in
            list.removeAll { $0.id == id }
        }
    }
}
