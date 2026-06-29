import SwiftUI
import DLNAKit

/// 検索フィルター用のタグ選択シート。タグを検索フィルターで絞り込み、タップでそのタグの検索結果へ。
/// （タグのリネーム・削除は TagEditorView 側）
struct TagFilterView: View {
    /// 選んだタグを検索フィルターに追加する。
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var expanded: Set<String> = []

    private let tags = TagsModel.shared

    private var filteredTags: [String] {
        tags.allTags().filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredTags.isEmpty {
                    ContentUnavailableView(
                        tags.allTags().isEmpty ? "タグがありません" : "一致するタグがありません",
                        systemImage: "tag"
                    )
                } else {
                    List {
                        ForEach(TagGrouping.grouped(filteredTags)) { group in
                            if let key = group.key {
                                // 見出しをタップで展開/折りたたみ。検索中は自動展開。
                                DisclosureGroup(isExpanded: expansionBinding(for: key)) {
                                    tagRows(group.tags)
                                } label: {
                                    Label("\(key)（\(group.tags.count)）", systemImage: "tag.square")
                                }
                            } else {
                                Section { tagRows(group.tags) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $filter, prompt: "タグを検索")
            .navigationTitle("タグで検索")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    /// グループの展開状態。検索中（filter 非空）は常に展開して結果を隠さない。
    private func expansionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { !filter.isEmpty || expanded.contains(key) },
            set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } }
        )
    }

    /// グループ内のタグ行（見出し以降のラベルを表示。タップで検索）。
    @ViewBuilder
    private func tagRows(_ groupTags: [String]) -> some View {
        ForEach(groupTags, id: \.self) { tag in
            Button {
                onSelect(tag)
                dismiss()
            } label: {
                HStack {
                    Label(TagGrouping.label(for: tag), systemImage: "tag")
                    Spacer()
                    Text("\(tags.usageCount(tag)) 本")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
