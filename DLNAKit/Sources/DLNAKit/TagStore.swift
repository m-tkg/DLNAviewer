import Foundation

/// 動画ごとのタグを端末ローカルに永続化するストア。
/// キーは安定識別子（UPnP の object id 等）。
public final class TagStore: @unchecked Sendable {
    private let core: JSONStoreCore<[String: [String]]>

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "videoTags") {
        core = JSONStoreCore(storage: storage, key: key, default: { [:] })
    }

    /// 指定 ID のタグ（昇順）。
    public func tags(for id: String) -> [String] {
        core.read { ($0[id] ?? []).sorted() }
    }

    /// タグ一覧を設定する（空なら削除）。空文字・重複（大小無視）は除外。
    public func setTags(_ tags: [String], for id: String) {
        let clean = dedupe(tags)
        core.mutate { dict in
            dict[id] = clean.isEmpty ? nil : clean
        }
    }

    public func all() -> [String: [String]] {
        core.read { $0 }
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
}
