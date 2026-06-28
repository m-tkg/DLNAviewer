import Foundation
import Observation
import AVFoundation
import CoreGraphics
import Vision
import DLNAKit

/// チャプター検出中の進行状況（進捗・件数・追加済み時刻）を保持する。
/// 追加済み時刻は、キャンセル時のロールバックに使う。
@MainActor
@Observable
final class ChapterRun {
    var progress: Double = 0
    var count: Int = 0
    /// 今回新規に追加したブックマーク時刻（既存と重複しなかったもの）。
    var addedTimes: [Double] = []
}

/// 動画から自動でチャプター（区切り時刻）を検出する。
/// 1) 埋め込みチャプター metadata があればそれを採用。
/// 2) 無ければフレームをサンプリングし、シーン変化（特徴量の差）で区切る。
enum ChapterDetector {
    struct Result: Sendable {
        /// metadata 由来なら true、自動検出なら false。
        var fromMetadata: Bool
        /// 途中でキャンセルされたら true。
        var cancelled: Bool
    }

    /// チャプターを検出する。重い処理なので進捗を `onProgress`（0...1）で、
    /// 検出したチャプター時刻をその都度 `onChapter` で通知する（リアルタイム反映用）。
    /// `Task` のキャンセルで中断する。
    static func detect(
        item: MediaItem,
        onProgress: @MainActor @Sendable @escaping (Double) -> Void = { _ in },
        onChapter: @MainActor @Sendable @escaping (Double) -> Void = { _ in }
    ) async -> Result {
        guard let url = await MainActor.run(body: { DownloadManager.shared.preferredURL(for: item) }) else {
            return Result(fromMetadata: false, cancelled: false)
        }
        let asset = AVURLAsset(url: url)

        // 動画長を確定（DIDL の duration を優先、無ければ asset から）。
        var duration = item.resources.first?.durationSeconds ?? 0
        if duration <= 0 {
            duration = (try? await asset.load(.duration).seconds) ?? 0
        }
        guard duration > 5 else { return Result(fromMetadata: false, cancelled: false) }

        // 1) 埋め込みチャプター。
        if let embedded = try? await embeddedChapters(asset: asset), embedded.count >= 2 {
            for time in embedded {
                if Task.isCancelled { return Result(fromMetadata: true, cancelled: true) }
                await onChapter(time)
            }
            await onProgress(1)
            return Result(fromMetadata: true, cancelled: false)
        }

        // 2) シーン変化検出（逐次通知）。
        let cancelled = await sceneChanges(
            url: url, duration: duration, onProgress: onProgress, onChapter: onChapter
        )
        await onProgress(1)
        return Result(fromMetadata: false, cancelled: cancelled)
    }

    // MARK: - 埋め込みチャプター

    private static func embeddedChapters(asset: AVURLAsset) async throws -> [Double] {
        let languages = Locale.preferredLanguages
        let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages)
        let times = groups
            .map { $0.timeRange.start.seconds }
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()
        return times
    }

    // MARK: - シーン変化検出

    /// フレームを順に解析し、シーン変化を見つけ次第 `onChapter` で通知する。
    /// 走査中の統計（平均+0.8σ）をしきい値に用いるストリーミング方式。
    /// - Returns: キャンセルされたら true。
    private static func sceneChanges(
        url: URL,
        duration: Double,
        onProgress: @MainActor @Sendable (Double) -> Void,
        onChapter: @MainActor @Sendable (Double) -> Void
    ) async -> Bool {
        // サンプル間隔: 最大約120枚に収める。短い動画は細かく、長い動画は粗く。
        let interval = max(10.0, duration / 120.0)
        let minSpacing = max(20.0, duration / 40.0)

        var previous: VNFeaturePrintObservation?
        var sum: Float = 0, sumSq: Float = 0, count = 0   // 距離の走査統計
        var lastChapter = -Double.greatestFiniteMagnitude
        var emitted = 0
        var t = 0.0

        while t < duration {
            if Task.isCancelled { return true }

            if let cg = await ThumbnailCache.shared.generate(
                from: url, at: t, tolerance: interval / 2, maxSize: 160
            ), let fp = featurePrint(cg) {
                if let prev = previous {
                    var d: Float = 0
                    if (try? fp.computeDistance(&d, to: prev)) != nil {
                        count += 1; sum += d; sumSq += d * d
                        // ある程度サンプルが貯まってから判定（早期の不安定さを回避）。
                        if count >= 5 {
                            let mean = sum / Float(count)
                            let variance = max(0, sumSq / Float(count) - mean * mean)
                            let std = variance.squareRoot()
                            if d >= mean + 0.8 * std, t - lastChapter >= minSpacing, emitted < 40 {
                                lastChapter = t
                                emitted += 1
                                await onChapter(t)
                            }
                        }
                    }
                }
                previous = fp
            }

            t += interval
            await onProgress(min(0.99, t / duration))
        }
        return false
    }

    private static func featurePrint(_ cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first as? VNFeaturePrintObservation
    }
}
