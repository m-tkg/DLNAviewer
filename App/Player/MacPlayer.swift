import SwiftUI
import AVKit
import AVFoundation
import DLNAKit

#if os(macOS)
struct MacPlayer: View {
    let item: MediaItem
    private var ratings: RatingsModel { RatingsModel.shared }
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
                    .contextMenu { RatingMenu(item: item, ratings: ratings) }
            } else {
                ContentUnavailableView(
                    "再生できません",
                    systemImage: "play.slash",
                    description: Text("このアイテムには再生可能なリソースがありません。")
                )
            }
        }
        .navigationTitle(item.title)
        .onAppear {
            guard player == nil, let url = DownloadManager.shared.preferredURL(for: item) else { return }
            let player = AVPlayer(playerItem: PlayerItemFactory.make(url: url))
            player.automaticallyWaitsToMinimizeStalling = false
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
#endif
