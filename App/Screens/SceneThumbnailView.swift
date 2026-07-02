import SwiftUI
import DLNAKit

/// 動画の指定時刻のシーンサムネイル（生成・キャッシュ）。
struct SceneThumbnailView: View {
    let item: MediaItem
    let time: Double
    var size: CGSize = CGSize(width: 100, height: 56)

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: time) { await load() }
    }

    private func load() async {
        // キーは persistentKey#秒 に統一（ThumbnailView の生成キャッシュと共有される）。
        // 旧 id@秒 キーのキャッシュは再生成可能なので破棄でよい。
        if let generated = await ThumbnailCache.shared.sceneImage(
            cacheKey: ThumbnailCache.sceneKey(for: item, at: time),
            url: DownloadManager.shared.preferredURL(for: item),
            at: time
        ) {
            image = generated
        }
    }
}
