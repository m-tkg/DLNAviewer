import SwiftUI
import AVFoundation
import ImageIO
import DLNAKit

/// 同時実行数を制限するシンプルな非同期セマフォ。
actor AsyncSemaphore {
    private let limit: Int
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { self.limit = limit }

    func wait() async {
        if count < limit { count += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            count = max(0, count - 1)
        } else {
            waiters.removeFirst().resume()   // 枠を次の待機者へ引き継ぐ（count は据え置き）
        }
    }
}

/// 生成済みサムネイル（CGImage）の簡易キャッシュ。
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    /// フレーム生成の同時実行数を制限する（リストスクロール時に生成が多発するのを防ぐ）。
    private let limiter = AsyncSemaphore(limit: 4)
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
        if Task.isCancelled { return nil }
        // 同時実行を制限。スクロールで画面外に消えてキャンセルされたものは生成しない。
        await limiter.wait()
        defer { Task { await limiter.signal() } }
        if Task.isCancelled { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    /// サーバー提供のサムネイル画像 URL を取得し、省メモリにダウンサンプリングしてキャッシュする。
    /// 一度取得すれば NSCache に残るので、フォルダを開き直しても即表示できる。
    func remoteImage(from url: URL, maxSize: CGFloat = 320) async -> CGImage? {
        let key = "remote#\(url.absoluteString)"
        if let cached = image(for: key) { return cached }
        if Task.isCancelled { return nil }
        await limiter.wait()
        defer { Task { await limiter.signal() } }
        if Task.isCancelled { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        store(cg, for: key)
        return cg
    }
}

/// 動画アイテムのサムネイルを表示する。
/// サーバー提供のサムネイル（albumArtURI / 画像 res）を優先し、無ければ動画から生成する。
struct ThumbnailView: View {
    let item: MediaItem
    /// nil の場合は親から与えられたフレームいっぱいに表示する。
    var size: CGSize? = nil

    @State private var image: CGImage?

    var body: some View {
        // 「このシーンをサムネイルにする」で時刻が設定されていれば、その時刻のフレームを優先。
        let overrideTime = ThumbnailsModel.shared.time(for: item)
        return Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .frame(width: size?.width, height: size?.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        // 上書き時刻が変わったら作り直す。
        .task(id: overrideTime) {
            await load(overrideTime: overrideTime)
        }
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .imageScale(.large)
            .foregroundStyle(.secondary)
    }

    /// 上書き時刻 → サーバー提供サムネ → 動画から生成 の順で取得する。
    /// いずれも `ThumbnailCache`（メモリ）に載るので、開き直したフォルダでは即表示される。
    private func load(overrideTime: Double?) async {
        if let overrideTime {
            await loadGenerated(at: overrideTime)
            return
        }
        if let url = item.thumbnailURL,
           let cached = await ThumbnailCache.shared.remoteImage(from: url) {
            image = cached
            return
        }
        await loadGenerated(at: 1)
    }

    private func loadGenerated(at seconds: Double) async {
        // ダウンロード済みならローカルファイルから生成（オフラインでも可）。
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return }
        let cacheKey = "\(item.persistentKey)#\(Int(seconds))"
        if let cached = ThumbnailCache.shared.image(for: cacheKey) {
            image = cached
            return
        }
        if let cg = await ThumbnailCache.shared.generate(from: url, at: seconds) {
            ThumbnailCache.shared.store(cg, for: cacheKey)
            image = cg
        }
    }
}
