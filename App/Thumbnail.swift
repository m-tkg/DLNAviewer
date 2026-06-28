import SwiftUI
import AVFoundation
import DLNAKit

/// 生成済みサムネイル（CGImage）の簡易キャッシュ。
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private final class Box { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private let cache = NSCache<NSString, Box>()

    func image(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func store(_ image: CGImage, for key: String) {
        cache.setObject(Box(image), forKey: key as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
    }

    /// 動画 URL から 1 フレーム（既定 1 秒地点）を生成する。
    func generate(from url: URL, maxSize: CGFloat = 320) async -> CGImage? {
        await generate(from: url, at: 1, tolerance: 2, maxSize: maxSize)
    }

    /// 動画 URL の指定秒のフレームを生成する。
    func generate(from url: URL, at seconds: Double, tolerance: Double = 1, maxSize: CGFloat = 320) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}

/// 動画アイテムのサムネイルを表示する。
/// サーバー提供のサムネイル（albumArtURI / 画像 res）を優先し、無ければ動画から生成する。
struct ThumbnailView: View {
    let item: MediaItem
    /// nil の場合は親から与えられたフレームいっぱいに表示する。
    var size: CGSize? = nil

    @State private var generated: CGImage?

    var body: some View {
        // 「このシーンをサムネイルにする」で時刻が設定されていれば、その時刻のフレームを優先。
        let overrideTime = ThumbnailsModel.shared.time(for: item)
        return Group {
            if overrideTime != nil {
                generatedImage
            } else if let url = item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                generatedImage
            }
        }
        .frame(width: size?.width, height: size?.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        // 上書き時刻が変わったら作り直す（生成表示が必要な場合のみ）。
        .task(id: overrideTime) {
            if overrideTime != nil || item.thumbnailURL == nil {
                await loadGenerated(at: overrideTime ?? 1)
            }
        }
    }

    @ViewBuilder
    private var generatedImage: some View {
        if let generated {
            Image(decorative: generated, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .imageScale(.large)
            .foregroundStyle(.secondary)
    }

    private func loadGenerated(at seconds: Double) async {
        // ダウンロード済みならローカルファイルから生成（オフラインでも可）。
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return }
        let cacheKey = "\(item.persistentKey)#\(Int(seconds))"
        if let cached = ThumbnailCache.shared.image(for: cacheKey) {
            generated = cached
            return
        }
        if let image = await ThumbnailCache.shared.generate(from: url, at: seconds) {
            ThumbnailCache.shared.store(image, for: cacheKey)
            generated = image
        }
    }
}
