import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
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

    /// ディスクキャッシュの保存先（Caches 配下。OS が容量逼迫時に自動 purge する）。
    private let diskDir: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// メモリ → ディスクの順でキャッシュを引く。ディスクヒット時はメモリにも載せ直す。
    func image(for key: String) -> CGImage? {
        if let mem = cache.object(forKey: key as NSString)?.image { return mem }
        guard let url = diskURL(for: key),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache.setObject(Box(cg), forKey: key as NSString)
        return cg
    }

    /// メモリとディスクの両方へ保存する（再起動後もディスクから即表示できる）。
    func store(_ image: CGImage, for key: String) {
        cache.setObject(Box(image), forKey: key as NSString)
        guard let url = diskURL(for: key),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    func clearAll() {
        cache.removeAllObjects()
        guard let diskDir else { return }
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    /// key（URL や persistentKey を含む）を SHA256 でハッシュ化してファイル名にする。
    private func diskURL(for key: String) -> URL? {
        guard let diskDir else { return nil }
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskDir.appendingPathComponent(name + ".jpg")
    }

    /// 動画 URL から 1 フレーム（既定 1 秒地点）を生成する。
    func generate(from url: URL, maxSize: CGFloat = 320) async -> CGImage? {
        await generate(from: url, at: 1, tolerance: 2, maxSize: maxSize)
    }

    /// 動画から 1 フレーム生成するまでの最大待ち時間。
    /// サーバーが動画ストリームへの応答をハングさせた場合でも、ここで必ず打ち切って
    /// `limiter` を解放する（さもないと同時実行枠 4 が恒久的に埋まり、アプリ全体の
    /// サムネイル生成が二度と進まなくなる）。
    private static let generationTimeout: Double = 10

    /// 動画 URL の指定秒のフレームを生成する。
    func generate(from url: URL, at seconds: Double, tolerance: Double = 1, maxSize: CGFloat = 320) async -> CGImage? {
        if Task.isCancelled { return nil }
        // 同時実行を制限。スクロールで画面外に消えてキャンセルされたものは生成しない。
        await limiter.wait()
        defer { Task { await limiter.signal() } }
        if Task.isCancelled { return nil }
        let asset = AVURLAsset(url: url)
        // cancelAllCGImageGeneration() は生成中でも任意のスレッドから呼んでよい仕様
        // （ドキュメントで明言されている）ため、タイムアウト用クロージャでの並行キャプチャは安全。
        nonisolated(unsafe) let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        let generated: CGImage?? = await AsyncTimeout.run(
            seconds: Self.generationTimeout,
            onTimeout: { generator.cancelAllCGImageGeneration() },
            operation: { try? await generator.image(at: time).image }
        )
        return generated ?? nil
    }

    /// 動画シーンサムネイルのキャッシュキー（`persistentKey#秒` に統一）。
    static func sceneKey(for item: MediaItem, at seconds: Double) -> String {
        "\(item.persistentKey)#\(Int(seconds))"
    }

    /// キャッシュ → 生成 → 保存 の順で動画シーンのサムネイルを取得する。
    /// `url`（ローカル/ストリーミングの再生 URL）が nil ならキャッシュヒットのみ。
    func sceneImage(cacheKey: String, url: URL?, at seconds: Double) async -> CGImage? {
        if let cached = image(for: cacheKey) { return cached }
        guard let url, let cg = await generate(from: url, at: seconds) else { return nil }
        store(cg, for: cacheKey)
        return cg
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
        if let cg = await ThumbnailCache.shared.sceneImage(
            cacheKey: ThumbnailCache.sceneKey(for: item, at: seconds),
            url: DownloadManager.shared.preferredURL(for: item),
            at: seconds
        ) {
            image = cg
        }
    }
}
