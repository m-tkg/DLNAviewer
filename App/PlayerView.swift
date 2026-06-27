import SwiftUI
import AVKit
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
    let item: MediaItem

    var body: some View {
        #if os(iOS)
        iOSPlayer(item: item)
        #else
        MacPlayer(item: item)
        #endif
    }
}

/// 評価（Like / Dislike / なし）を選ぶメニュー。長押し・右クリックから使う。
struct RatingMenu: View {
    let item: MediaItem
    let ratings: RatingsModel

    var body: some View {
        Picker("評価", selection: Binding(
            get: { ratings.rating(for: item) },
            set: { ratings.set($0, for: item) }
        )) {
            Label("Like", systemImage: "hand.thumbsup").tag(Rating.like)
            Label("Dislike", systemImage: "hand.thumbsdown").tag(Rating.dislike)
            Label("評価なし", systemImage: "minus").tag(Rating.none)
        }
    }
}

// MARK: - macOS

#if os(macOS)
private struct MacPlayer: View {
    let item: MediaItem
    @Environment(RatingsModel.self) private var ratings
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
            guard player == nil, let url = item.preferredVideoResource?.url else { return }
            let playerItem = AVPlayerItem(asset: AVURLAsset(url: url))
            playerItem.preferredForwardBufferDuration = 60
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
#endif

// MARK: - iOS

#if os(iOS)
private struct iOSPlayer: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @Environment(RatingsModel.self) private var ratings

    @State private var player = AVPlayer()
    @State private var hasSource = true
    @State private var controlsVisible = true
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var hideTask: Task<Void, Never>?

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if hasSource {
                PlayerLayerView(player: player).ignoresSafeArea()
                if controlsVisible {
                    controlsOverlay.transition(.opacity)
                }
            } else {
                ContentUnavailableView(
                    "再生できません",
                    systemImage: "play.slash",
                    description: Text("このアイテムには再生可能なリソースがありません。")
                )
                .foregroundStyle(.white)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
            if controlsVisible { scheduleAutoHide() }
        }
        // 長押しで評価メニュー。
        .contextMenu {
            RatingMenu(item: item, ratings: ratings)
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!controlsVisible)
        .onReceive(ticker) { _ in tick() }
        .onAppear { setUp() }
        .onDisappear {
            player.pause()
            hideTask?.cancel()
            OrientationManager.shared.unlock()
        }
    }

    // MARK: コントロールオーバーレイ

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            centerControls
            Spacer()
            bottomBar
        }
        .foregroundStyle(.white)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            Text(item.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button { toggleOrientation() } label: {
                Image(systemName: "rotate.right").font(.title3)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var centerControls: some View {
        HStack(spacing: 44) {
            Button { skip(-10) } label: {
                Image(systemName: "gobackward.10")
            }
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 60)
            }
            Button { skip(10) } label: {
                Image(systemName: "goforward.10")
            }
        }
        .font(.system(size: 44))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text(Self.timeString(currentTime))
                .font(.caption.monospacedDigit())
            Slider(
                value: $currentTime,
                in: 0...max(duration, 0.1)
            ) { editing in
                isScrubbing = editing
                if editing {
                    hideTask?.cancel()
                } else {
                    seek(to: currentTime)
                    scheduleAutoHide()
                }
            }
            Text(Self.timeString(duration))
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: 再生制御

    private func setUp() {
        guard let url = item.preferredVideoResource?.url else {
            hasSource = false
            return
        }
        let playerItem = AVPlayerItem(asset: AVURLAsset(url: url))
        playerItem.preferredForwardBufferDuration = 60
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.replaceCurrentItem(with: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.play()
        isPlaying = true
        scheduleAutoHide()
    }

    private func tick() {
        if !isScrubbing {
            let t = player.currentTime().seconds
            if t.isFinite { currentTime = t }
        }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            duration = d
        }
        isPlaying = player.timeControlStatus == .playing
    }

    private func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            hideTask?.cancel()       // 停止中はコントロールを出したままにする
        } else {
            player.play()
            isPlaying = true
            scheduleAutoHide()
        }
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func skip(_ delta: Double) {
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, currentTime + delta))
        currentTime = target
        seek(to: target)
        scheduleAutoHide()
    }

    /// 一定時間操作が無ければコントロール（＝タイトルも）を隠す。停止中は隠さない。
    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard controlsVisible else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled, isPlaying, !isScrubbing {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
            }
        }
    }

    /// 端末の回転ロック中でも縦横を強制的に切り替える。
    private func toggleOrientation() {
        if OrientationManager.shared.isLandscape {
            OrientationManager.shared.force(.portrait)
        } else {
            OrientationManager.shared.force(.landscapeRight)
        }
        scheduleAutoHide()
    }

    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// AVPlayer を `AVPlayerLayer` で描画するだけのビュー（コントロールは持たない）。
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
