#if os(iOS)
import Foundation
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// シーン画像を Vision で解析し、Foundation Models（オンデバイス）で具体的な説明文にする。
/// （オンデバイスモデルは画像入力できないため、Vision の解析結果を橋渡しに使う）
enum SceneDescriber {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// 画像を解析して、できるだけ具体的な日本語のシーン説明を生成する。
    static func describe(_ image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        #if canImport(FoundationModels)
        // iOS 27+: 画像を直接モデルへ渡してマルチモーダルに説明する（最も具体的）。
        if #available(iOS 27.0, *),
           case .available = SystemLanguageModel.default.availability,
           let text = await describeMultimodal(cgImage, orientation: cgOrientation(image.imageOrientation)) {
            return text
        }
        #endif

        // iOS 26 / マルチモーダル失敗時: Vision 解析 → テキストモデルで説明。
        let signals = analyze(cgImage)
        guard signals.hasContent else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            // 緩和ガードレール（コンテンツ変換用途）で誤検知を減らす。
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            let session = LanguageModelSession(model: model)
            if let response = try? await session.respond(to: signals.prompt) {
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        #endif
        // Foundation Models が使えない場合は検出内容をそのまま返す。
        return signals.fallbackText
    }

    #if canImport(FoundationModels)
    /// iOS 27+ のマルチモーダル入力で、画像を直接モデルに渡して説明させる。
    @available(iOS 27.0, *)
    private static func describeMultimodal(
        _ cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async -> String? {
        // 緩和ガードレール（コンテンツ変換用途）で誤検知を減らす。
        // 万一画像入力で弾かれても、呼び出し元が Vision 経路へフォールバックする。
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model)
        do {
            let response = try await session.respond {
                Attachment(cgImage, orientation: orientation)
                """
                この画像に写っているシーンを、日本語でできるだけ具体的に説明してください。
                場所・状況・登場する人物や物・画面内の文字（テロップや字幕）などを、分かる範囲で具体的に3〜4文で。
                断定できない点は「〜のように見える」と表現し、見えないことは書かないでください。
                """
            }
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
    #endif

    /// UIImage.Orientation → CGImagePropertyOrientation。
    private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// 動画から数フレームを等間隔でサンプリングして返す（案B 共通）。
    static func videoFrames(url: URL, durationSeconds: Double?) async -> [CGImage] {
        let duration = durationSeconds ?? 0
        let times: [Double] = duration > 1
            ? [0.1, 0.3, 0.5, 0.7, 0.9].map { $0 * duration }
            : [1, 3, 5, 8]

        var frames: [CGImage] = []
        for time in times {
            if let cgImage = await ThumbnailCache.shared.generate(
                from: url, at: time, tolerance: 1, maxSize: 720
            ) {
                frames.append(cgImage)
            }
        }
        return frames
    }

    /// サンプリングしたフレームを分類し、ラベルを信頼度の合計順に集約する（iOS 26 経路）。
    static func videoLabels(url: URL, durationSeconds: Double?) async -> [String] {
        let frames = await videoFrames(url: url, durationSeconds: durationSeconds)
        var totals: [String: Float] = [:]
        for frame in frames {
            for result in classify(frame) {
                totals[result.label, default: 0] += result.confidence
            }
        }
        return totals.sorted { $0.value > $1.value }.prefix(12).map { $0.key }
    }

    // MARK: - Vision 解析

    /// 1 枚の画像から複数の手がかり（物体・文字・人物・動物）をまとめて抽出する。
    private struct Signals {
        var labels: [String] = []
        var texts: [String] = []
        var faceCount: Int = 0
        var animals: [String] = []

        var hasContent: Bool {
            !labels.isEmpty || !texts.isEmpty || faceCount > 0 || !animals.isEmpty
        }

        /// Foundation Models へ渡す、具体的な描写を促すプロンプト。
        var prompt: String {
            var lines: [String] = []
            if !labels.isEmpty { lines.append("- 物体・シーン: \(labels.prefix(10).joined(separator: ", "))") }
            if faceCount > 0 { lines.append("- 人物: 約\(faceCount)人") }
            if !animals.isEmpty { lines.append("- 動物: \(animals.joined(separator: ", "))") }
            if !texts.isEmpty {
                let quoted = texts.prefix(8).map { "「\($0)」" }.joined(separator: " ")
                lines.append("- 画面内の文字: \(quoted)")
            }
            return """
            以下は1枚の画像から自動検出した情報です。これらに基づいて、画像のシーンをできるだけ具体的に日本語で描写してください。
            \(lines.joined(separator: "\n"))

            条件:
            - 場所・状況・写っているもの・人数・画面内の文字を、分かる範囲で具体的に盛り込む。
            - 3〜4文程度。箇条書きや前置きは不要、説明文のみ。
            - 検出情報にないことは断定せず、推測する場合は「〜のように見える」とする。
            """
        }

        /// モデルが使えないときの素朴な要約。
        var fallbackText: String {
            var parts: [String] = []
            if !labels.isEmpty { parts.append(labels.prefix(6).joined(separator: " / ")) }
            if faceCount > 0 { parts.append("人物 約\(faceCount)人") }
            if !animals.isEmpty { parts.append(animals.joined(separator: " / ")) }
            if !texts.isEmpty { parts.append("文字: " + texts.prefix(5).map { "「\($0)」" }.joined(separator: " ")) }
            return parts.joined(separator: "\n")
        }
    }

    /// 物体分類・文字認識・顔検出・動物認識を 1 回のハンドラ実行でまとめて行う。
    private static func analyze(_ cgImage: CGImage) -> Signals {
        let classifyRequest = VNClassifyImageRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["ja-JP", "en-US"]
        textRequest.usesLanguageCorrection = true
        let faceRequest = VNDetectFaceRectanglesRequest()
        let animalRequest = VNRecognizeAnimalsRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try? handler.perform([classifyRequest, textRequest, faceRequest, animalRequest])

        var signals = Signals()

        if let observations = classifyRequest.results as? [VNClassificationObservation] {
            signals.labels = observations
                .filter { $0.confidence > 0.12 }
                .prefix(10)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }
        if let observations = textRequest.results as? [VNRecognizedTextObservation] {
            signals.texts = observations
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 }
                .prefix(10)
                .map { $0 }
        }
        if let observations = faceRequest.results as? [VNFaceObservation] {
            signals.faceCount = observations.count
        }
        if let observations = animalRequest.results as? [VNRecognizedObjectObservation] {
            signals.animals = observations
                .compactMap { $0.labels.first?.identifier }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        }
        return signals
    }

    /// 動画フレーム集約用の軽量分類（信頼度つきラベル）。
    private static func classify(_ cgImage: CGImage) -> [(label: String, confidence: Float)] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return [] }
        let observations = (request.results as? [VNClassificationObservation]) ?? []
        return observations
            .filter { $0.confidence > 0.15 }
            .prefix(8)
            .map { (label: $0.identifier.replacingOccurrences(of: "_", with: " "),
                    confidence: $0.confidence) }
    }
}
#endif
