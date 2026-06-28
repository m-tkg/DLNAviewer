import Foundation
import CoreGraphics
import DLNAKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// タグ提案の結果（候補が空のときは理由を message に入れる）。
struct TagSuggestionResult {
    var tags: [String] = []
    var message: String? = nil
}

/// Foundation Models（オンデバイス Apple Intelligence）で動画のタグを提案する。
enum TagSuggester {
    /// この端末で利用可能か（Apple Intelligence 対応・有効）。
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// 動画のメタデータ（必要なら映像解析ラベル）からタグ候補を生成する。
    /// - Parameters:
    ///   - item: 対象の動画。
    ///   - folderName: 親フォルダ名（あれば文脈として渡す）。
    ///   - existing: 既に付いているタグ（提案から除外）。
    ///   - vocabulary: 既存タグ語彙（可能ならこの中から優先するよう促す）。
    ///   - sceneLabels: 映像解析（Vision）で得たラベル（案B。無ければ空）。
    ///   - frames: 動画フレーム画像（iOS 27+ でモデルへ直接渡す。無ければテキストのみ）。
    static func suggest(
        item: MediaItem,
        folderName: String?,
        existing: [String],
        vocabulary: [String],
        sceneLabels: [String] = [],
        frames: [CGImage] = []
    ) async -> TagSuggestionResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                let prompt = buildPrompt(
                    item: item,
                    folderName: folderName,
                    existing: existing,
                    vocabulary: vocabulary,
                    sceneLabels: sceneLabels
                )
                // iOS 27+: フレーム画像があれば直接モデルへ渡す（マルチモーダル）。
                if #available(iOS 27.0, macOS 27.0, *), !frames.isEmpty {
                    if let result = await suggestMultimodal(prompt: prompt, frames: frames, exclude: existing) {
                        return result
                    }
                    // 失敗時はテキスト経路へフォールバック。
                }
                // タグ付け用途のモデル＋緩和ガードレール（誤検知を減らす。完全無効化は不可）。
                let model = SystemLanguageModel(useCase: .contentTagging, guardrails: .permissiveContentTransformations)
                let session = LanguageModelSession(model: model)
                do {
                    let response = try await session.respond(to: prompt)
                    let tags = parse(response.content, exclude: existing)
                    if tags.isEmpty {
                        return TagSuggestionResult(message: "候補を抽出できませんでした。もう一度お試しください。")
                    }
                    return TagSuggestionResult(tags: tags)
                } catch {
                    return TagSuggestionResult(message: "生成に失敗しました: \(error.localizedDescription)")
                }
            case .unavailable(let reason):
                return TagSuggestionResult(message: "Apple Intelligence を利用できません（\(describe(reason))）。")
            }
        }
        #endif
        return TagSuggestionResult(message: "この端末では AI 提案を利用できません。")
    }

    #if canImport(FoundationModels)
    /// iOS 27+: フレーム画像を直接モデルへ渡してタグを生成する。
    @available(iOS 27.0, macOS 27.0, *)
    private static func suggestMultimodal(
        prompt: String,
        frames: [CGImage],
        exclude: [String]
    ) async -> TagSuggestionResult? {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model)
        do {
            let response = try await session.respond {
                for frame in frames.prefix(3) {
                    Attachment(frame)
                }
                prompt + "\n上の画像（動画の代表フレーム）も踏まえてタグを付けてください。"
            }
            let tags = parse(response.content, exclude: exclude)
            return tags.isEmpty ? nil : TagSuggestionResult(tags: tags)
        } catch {
            return nil
        }
    }
    #endif

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "対応していない端末"
        case .appleIntelligenceNotEnabled: return "設定で Apple Intelligence が未有効"
        case .modelNotReady: return "モデル準備中。しばらく後に再試行"
        @unknown default: return "理由不明"
        }
    }
    #endif

    /// メタデータを箇条書きにしたプロンプトを組み立てる。
    private static func buildPrompt(
        item: MediaItem,
        folderName: String?,
        existing: [String],
        vocabulary: [String],
        sceneLabels: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("タイトル: \(item.title)")

        // ファイル名（タイトルと実質同じなら省く）。
        if let fileName = item.primaryURL?.lastPathComponent
            .removingPercentEncoding ?? item.primaryURL?.lastPathComponent,
           !fileName.isEmpty,
           !item.title.localizedCaseInsensitiveContains(fileName),
           !fileName.localizedCaseInsensitiveContains(item.title) {
            lines.append("ファイル名: \(fileName)")
        }
        if let folderName, !folderName.isEmpty {
            lines.append("フォルダ: \(folderName)")
        }
        if let res = item.resources.first {
            if let resolution = res.resolution, !resolution.isEmpty {
                lines.append("解像度: \(resolution)")
            }
            if let seconds = res.durationSeconds, seconds > 0 {
                lines.append("長さ: 約\(Int((seconds / 60).rounded()))分")
            }
        }
        if !sceneLabels.isEmpty {
            lines.append("映像から検出: \(sceneLabels.prefix(12).joined(separator: ", "))")
        }
        if !vocabulary.isEmpty {
            lines.append("既存タグ（可能ならこの中から優先）: \(vocabulary.prefix(40).joined(separator: ", "))")
        }
        if !existing.isEmpty {
            lines.append("既に付いているタグ（除外）: \(existing.joined(separator: ", "))")
        }

        return """
        次の動画情報から、内容を表す短いタグを最大5個、日本語で「カンマ区切りのみ」出力してください。説明や記号・番号・補足は不要。
        \(lines.joined(separator: "\n"))
        """
    }

    private static func parse(_ text: String, exclude: [String]) -> [String] {
        let excludeLower = Set(exclude.map { $0.lowercased() })
        let separators = CharacterSet(charactersIn: ",、\n・/|")
        // 行頭の番号・記号（"1." "- " "* " "•" "#"）と前後の記号を除去する。
        let trimSet = CharacterSet(charactersIn: " 　\t-*•#。.")
        return text
            .components(separatedBy: separators)
            .map { component -> String in
                var token = component.trimmingCharacters(in: .whitespacesAndNewlines)
                // "1." や "1)" のような行頭番号を落とす。
                if let range = token.range(of: #"^\s*\d+[.)、]\s*"#, options: .regularExpression) {
                    token.removeSubrange(range)
                }
                return token.trimmingCharacters(in: trimSet)
            }
            .filter { !$0.isEmpty && $0.count <= 20 && !excludeLower.contains($0.lowercased()) }
            .reduce(into: [String]()) { result, tag in
                if !result.contains(where: { $0.lowercased() == tag.lowercased() }) { result.append(tag) }
            }
            .prefix(5)
            .map { String($0) }
    }
}
