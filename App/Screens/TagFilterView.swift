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
                            // 見出しをタップで展開/折りたたみ。検索中は自動展開。
                            if group.key != nil {
                                TagGroupDisclosure(group: group, forceExpanded: !filter.isEmpty,
                                                   expanded: $expanded, row: tagRow)
                            } else {
                                Section {
                                    TagGroupDisclosure(group: group, forceExpanded: !filter.isEmpty,
                                                       expanded: $expanded, row: tagRow)
                                }
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

    /// タグ 1 行分（見出し以降のラベルを表示。タップで検索）。
    private func tagRow(_ tag: String) -> some View {
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
