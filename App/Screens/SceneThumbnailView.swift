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
        let key = "\(item.id)@\(Int(time))"
        if let cached = ThumbnailCache.shared.image(for: key) {
            image = cached
            return
        }
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return }
        if let generated = await ThumbnailCache.shared.generate(from: url, at: time) {
            ThumbnailCache.shared.store(generated, for: key)
            image = generated
        }
    }
}
