import SwiftUI
import AVKit
import AVFoundation
import DLNAKit
#if os(iOS)
import Combine
import UIKit
#endif

/// 動画再生画面。
///
/// iOS は自前のコントロール（再生/停止/シーク）とタイトルを 1 つのオーバーレイにまとめ、
/// 「コントロール表示中だけタイトルも表示」を満たす。macOS は標準の `VideoPlayer` を使う。
struct PlayerView: View {
    let items: [MediaItem]
    let startIndex: Int

    private var safeIndex: Int { min(max(startIndex, 0), max(items.count - 1, 0)) }

    var body: some View {
        #if os(iOS)
        iOSPlayer(items: items, startIndex: safeIndex)
        #else
        MacPlayer(item: items[safeIndex])
        #endif
    }
}
