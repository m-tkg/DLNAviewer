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
                    List(filteredTags, id: \.self) { tag in
                        Button {
                            onSelect(tag)
                            dismiss()
                        } label: {
                            HStack {
                                Label(tag, systemImage: "tag")
                                Spacer()
                                Text("\(tags.usageCount(tag)) 本")
                                    .foregroundStyle(.secondary)
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
}
