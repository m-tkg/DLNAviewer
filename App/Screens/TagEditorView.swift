import SwiftUI
import DLNAKit

/// 動画のタグを編集するシート。既存タグの自動補完つき。
struct TagEditorView: View {
    let item: MediaItem
    var folderName: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var deleting: String?
    @State private var aiSuggestions: [String] = []
    @State private var aiMessage: String?
    @State private var isSuggesting = false
    @State private var isScanningVideo = false
    @State private var expandedSuggestions: Set<String> = []
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
                        .noAutocapitalization()
                        .onSubmit(commitInput)

                    if canAddNew {
                        Button {
                            commitInput()
                        } label: {
                            Label("「\(trimmed)」を追加", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("タグを追加")
                } footer: {
                    Text("入力すると既存のタグが候補に表示されます。「aaa:bbb」の形式は aaa ごとにまとめて表示します。タグを長押しで名前変更・削除できます。")
                }

                // 自動補完候補（aaa:bbb は aaa ごとにグループ表示。見出しタップで展開。
                // 入力中は自動展開して候補を隠さない）。
                ForEach(TagGrouping.grouped(suggestions)) { group in
                    Section {
                        TagGroupDisclosure(group: group, forceExpanded: !trimmed.isEmpty,
                                           expanded: $expandedSuggestions, row: suggestionRow)
                    }
                }

                if TagSuggester.isAvailable {
                    Section("AI 提案") {
                        Button {
                            Task {
                                isSuggesting = true
                                aiMessage = nil
                                let result = await TagSuggester.suggest(
                                    item: item,
                                    folderName: folderName,
                                    existing: tags.tags(for: item),
                                    vocabulary: tags.allTags()
                                )
                                aiSuggestions = result.tags
                                aiMessage = result.message
                                isSuggesting = false
                            }
                        } label: {
                            if isSuggesting {
                                HStack { ProgressView(); Text("生成中…") }
                            } else {
                                Label("AI でタグを提案", systemImage: "sparkles")
                            }
                        }
                        .disabled(isSuggesting || isScanningVideo)

                        #if os(iOS)
                        // 案B: 映像も解析して提案（時間がかかるので明示操作）。
                        if let url = item.primaryURL {
                            Button {
                                Task {
                                    isScanningVideo = true
                                    aiMessage = nil
                                    let duration = item.resources.first?.durationSeconds
                                    let result: TagSuggestionResult
                                    if #available(iOS 27.0, *) {
                                        // iOS 27+: フレーム画像を直接モデルへ渡す。
                                        let frames = await SceneDescriber.videoFrames(
                                            url: url, durationSeconds: duration
                                        )
                                        result = await TagSuggester.suggest(
                                            item: item,
                                            folderName: folderName,
                                            existing: tags.tags(for: item),
                                            vocabulary: tags.allTags(),
                                            frames: frames
                                        )
                                    } else {
                                        // iOS 26: Vision でラベル化して渡す。
                                        let labels = await SceneDescriber.videoLabels(
                                            url: url, durationSeconds: duration
                                        )
                                        result = await TagSuggester.suggest(
                                            item: item,
                                            folderName: folderName,
                                            existing: tags.tags(for: item),
                                            vocabulary: tags.allTags(),
                                            sceneLabels: labels
                                        )
                                    }
                                    aiSuggestions = result.tags
                                    aiMessage = result.message
                                    isScanningVideo = false
                                }
                            } label: {
                                if isScanningVideo {
                                    HStack { ProgressView(); Text("映像を解析中…") }
                                } else {
                                    Label("映像も解析して提案", systemImage: "film")
                                }
                            }
                            .disabled(isSuggesting || isScanningVideo)
                        }
                        #endif

                        if let aiMessage {
                            Text(aiMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(aiSuggestions, id: \.self) { tag in
                            Button {
                                tags.add(tag, for: item)
                                aiSuggestions.removeAll { $0 == tag }
                            } label: {
                                Label(tag, systemImage: "sparkles")
                            }
                        }
                    }
                }
            }
            .navigationTitle("タグ")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .alert("タグの名前を変更", isPresented: Binding(presenting: $renaming)) {
                TextField("新しい名前", text: $renameText)
                Button("変更") {
                    if let old = renaming { tags.renameTag(old, to: renameText) }
                    renaming = nil
                }
                Button("キャンセル", role: .cancel) { renaming = nil }
            }
            .alert("タグを削除", isPresented: Binding(presenting: $deleting)) {
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

    /// 補完候補 1 行分（ラベルを表示。タップでこの動画に付与）。
    private func suggestionRow(_ tag: String) -> some View {
        Button {
            tags.add(tag, for: item)
            input = ""
        } label: {
            Label(TagGrouping.label(for: tag), systemImage: "tag")
        }
        .contextMenu { tagManageMenu(tag) }
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
