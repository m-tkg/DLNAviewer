import Foundation

/// `aaa:bbb` 形式のタグを「グループ見出し（aaa）」と「ラベル（bbb）」に分解し、
/// 一覧をグループ分けするための純粋ロジック。タグ文字列自体は変更しない。
public enum TagGrouping {
    /// グループ見出し（最初のコロンより前）。コロンが無い／見出しが空なら nil。
    public static func groupKey(for tag: String) -> String? {
        guard let i = tag.firstIndex(of: ":") else { return nil }
        let key = tag[..<i].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    /// グループ内で表示するラベル（最初のコロンより後ろ）。
    /// グループ無し、またはコロン後が空なら元のタグをそのまま返す。
    public static func label(for tag: String) -> String {
        guard groupKey(for: tag) != nil, let i = tag.firstIndex(of: ":") else { return tag }
        let rest = tag[tag.index(after: i)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? tag : rest
    }

    /// タグ群をグループごとにまとめて返す。名前付きグループを見出し名順、
    /// グループ無し（コロン無し）は末尾の見出し無しグループにまとめる。各グループ内はラベル順。
    public static func grouped(_ tags: [String]) -> [TagGroup] {
        var named: [String: [String]] = [:]
        var ungrouped: [String] = []
        for tag in tags {
            if let key = groupKey(for: tag) {
                named[key, default: []].append(tag)
            } else {
                ungrouped.append(tag)
            }
        }
        func byLabel(_ a: String, _ b: String) -> Bool {
            label(for: a).localizedCaseInsensitiveCompare(label(for: b)) == .orderedAscending
        }
        var result = named
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { TagGroup(key: $0.key, tags: $0.value.sorted(by: byLabel)) }
        if !ungrouped.isEmpty {
            result.append(TagGroup(key: nil, tags: ungrouped.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }))
        }
        return result
    }
}

/// 1 つのタググループ（見出しと、それに属するタグ群）。
public struct TagGroup: Identifiable, Hashable, Sendable {
    /// グループ見出し。nil はグループ無し（見出し無しで表示する）。
    public let key: String?
    public let tags: [String]
    public var id: String { key ?? "" }

    public init(key: String?, tags: [String]) {
        self.key = key
        self.tags = tags
    }
}
