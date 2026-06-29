import Foundation
import Testing
@testable import DLNAKit

@Suite("TagGrouping")
struct TagGroupingTests {
    @Test("コロンの前がグループ見出しになる")
    func groupKey() {
        #expect(TagGrouping.groupKey(for: "actor:tanaka") == "actor")
        #expect(TagGrouping.groupKey(for: "place:tokyo") == "place")
    }

    @Test("コロンが無ければグループ無し（nil）")
    func noColon() {
        #expect(TagGrouping.groupKey(for: "comedy") == nil)
    }

    @Test("先頭がコロン・見出しが空ならグループ無し")
    func leadingColon() {
        #expect(TagGrouping.groupKey(for: ":bbb") == nil)
        #expect(TagGrouping.groupKey(for: "  :bbb") == nil)
    }

    @Test("ラベルはコロンの後ろ。複数コロンは最初で分割")
    func label() {
        #expect(TagGrouping.label(for: "actor:tanaka") == "tanaka")
        #expect(TagGrouping.label(for: "a:b:c") == "b:c")
        #expect(TagGrouping.label(for: "comedy") == "comedy")
    }

    @Test("コロン後が空ならラベルは元のタグ")
    func emptyLabel() {
        #expect(TagGrouping.label(for: "actor:") == "actor:")
    }

    @Test("グループごとにまとまり、見出し名順・グループ無しは末尾")
    func grouped() {
        let groups = TagGrouping.grouped(["place:tokyo", "actor:suzuki", "comedy", "actor:tanaka"])
        #expect(groups.map(\.key) == ["actor", "place", nil])
        #expect(groups[0].tags == ["actor:suzuki", "actor:tanaka"])   // ラベル順
        #expect(groups[1].tags == ["place:tokyo"])
        #expect(groups[2].tags == ["comedy"])
    }

    @Test("グループ無しだけなら見出し無しセクション 1 つ")
    func ungroupedOnly() {
        let groups = TagGrouping.grouped(["beta", "alpha"])
        #expect(groups.count == 1)
        #expect(groups[0].key == nil)
        #expect(groups[0].tags == ["alpha", "beta"])
    }

    @Test("空配列なら空")
    func empty() {
        #expect(TagGrouping.grouped([]).isEmpty)
    }
}
