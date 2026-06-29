import SwiftUI
import DLNAKit

/// 検索フィルター用のタグ選択シート。タグを検索フィルターで絞り込み、タップでそのタグの検索結果へ。
/// （タグのリネーム・削除は TagEditorView 側）
struct TagFilterView: View {
    /// 選んだタグを検索フィルターに追加する。
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

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
                                Section(key) { tagRows(group.tags) }
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
