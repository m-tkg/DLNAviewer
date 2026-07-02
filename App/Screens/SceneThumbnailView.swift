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

/// 秒数を mm:ss / h:mm:ss にする。
func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}
