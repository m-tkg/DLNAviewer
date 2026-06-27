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
        Group {
            if let url = item.thumbnailURL {
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
            } else if let generated {
                Image(decorative: generated, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
                    .task { await loadGenerated() }
            }
        }
        .frame(width: size?.width, height: size?.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .imageScale(.large)
            .foregroundStyle(.secondary)
    }

    private func loadGenerated() async {
        // ダウンロード済みならローカルファイルから生成（オフラインでも可）。
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return }
        if let cached = ThumbnailCache.shared.image(for: item.id) {
            generated = cached
            return
        }
        if let image = await ThumbnailCache.shared.generate(from: url) {
            ThumbnailCache.shared.store(image, for: item.id)
            generated = image
        }
    }
}
