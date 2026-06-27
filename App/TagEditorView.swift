import SwiftUI
import DLNAKit

/// 動画のタグを編集するシート。既存タグの自動補完つき。
struct TagEditorView: View {
    let item: MediaItem

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var deleting: String?
    private let tags = TagsModel.shared

    private var trimmed: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 入力に一致する既存タグ（適用済みは除外）。自動補完候補。
    private var suggestions: [String] {
        let current = Set(tags.tags(for: item).map { $0.lowercased() })
        return tags.allTags().filter { tag in
            !current.contains(tag.lowercased())
                && (trimmed.isEmpty || tag.localizedCaseInsensitiveContains(trimmed))
        }
    }

    /// 入力したテキストが新規タグかどうか（候補にも適用済みにも無い）。
    private var canAddNew: Bool {
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        let existing = (tags.tags(for: item) + tags.allTags()).map { $0.lowercased() }
        return !existing.contains(lower)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("この動画のタグ") {
                    let current = tags.tags(for: item)
                    if current.isEmpty {
                        Text("タグなし").foregroundStyle(.secondary)
                    } else {
                        ForEach(current, id: \.self) { tag in
                            Label(tag, systemImage: "tag")
                                .swipeActions {
                                    Button(role: .destructive) {
                                        tags.remove(tag, for: item)
                                    } label: {
                                        Label("この動画から外す", systemImage: "minus.circle")
                                    }
                                }
                                .contextMenu { tagManageMenu(tag) }
                        }
                    }
                }

                Section {
                    TextField("タグを入力", text: $input)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(commitInput)

                    if canAddNew {
                        Button {
                            commitInput()
                        } label: {
                            Label("「\(trimmed)」を追加", systemImage: "plus.circle")
                        }
                    }
                    // 自動補完候補
                    ForEach(suggestions, id: \.self) { tag in
                        Button {
                            tags.add(tag, for: item)
                            input = ""
                        } label: {
                            Label(tag, systemImage: "tag")
                        }
                        .contextMenu { tagManageMenu(tag) }
                    }
                } header: {
                    Text("タグを追加")
                } footer: {
                    Text("入力すると既存のタグが候補に表示されます。タグを長押しで名前変更・削除できます。")
                }
            }
            .navigationTitle("タグ")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .alert("タグの名前を変更", isPresented: Binding(
                get: { renaming != nil }, set: { if !$0 { renaming = nil } }
            )) {
                TextField("新しい名前", text: $renameText)
                Button("変更") {
                    if let old = renaming { tags.renameTag(old, to: renameText) }
                    renaming = nil
                }
                Button("キャンセル", role: .cancel) { renaming = nil }
            }
            .alert("タグを削除", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            )) {
                Button("削除", role: .destructive) {
                    if let tag = deleting { tags.deleteTag(tag) }
                    deleting = nil
                }
                Button("キャンセル", role: .cancel) { deleting = nil }
            } message: {
                if let tag = deleting {
                    let count = tags.usageCount(tag)
                    if count > 0 {
                        Text("「\(tag)」は \(count) 本の動画で使われています。削除するとそれらの動画からも外れます。")
                    } else {
                        Text("「\(tag)」を削除します。")
                    }
                }
            }
        }
    }

    /// タグの一括管理（名前変更・削除）メニュー。長押しから使う。
    @ViewBuilder
    private func tagManageMenu(_ tag: String) -> some View {
        Button {
            renameText = tag
            renaming = tag
        } label: {
            Label("名前を変更…（全動画）", systemImage: "pencil")
        }
        Button(role: .destructive) {
            deleting = tag
        } label: {
            Label("タグを削除（全動画）", systemImage: "trash")
        }
    }

    private func commitInput() {
        guard !trimmed.isEmpty else { return }
        tags.add(trimmed, for: item)
        input = ""
    }
}
