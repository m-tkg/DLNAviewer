import SwiftUI
import DLNAKit

/// タググループ 1 つ分の表示。見出し付きグループは DisclosureGroup（タップで展開/折りたたみ）、
/// 見出し無しグループは行をそのまま並べる。TagEditorView / TagFilterView で共用。
struct TagGroupDisclosure<Row: View>: View {
    let group: TagGroup
    /// true なら常に展開する（検索・入力中に候補を隠さないため）。
    let forceExpanded: Bool
    @Binding var expanded: Set<String>
    /// グループ内の 1 タグ分の行。
    @ViewBuilder let row: (String) -> Row

    var body: some View {
        if let key = group.key {
            DisclosureGroup(isExpanded: expansionBinding(for: key)) {
                rows
            } label: {
                Label("\(key)（\(group.tags.count)）", systemImage: "tag.square")
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        ForEach(group.tags, id: \.self) { row($0) }
    }

    private func expansionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { forceExpanded || expanded.contains(key) },
            set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } }
        )
    }
}
