#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit
import DLNAKit

/// 再生（AVPlayer・PiP・描画レイヤー）を画面遷移より長く保持する永続モデル。
/// これにより「PiP のままリストへ戻っても再生が続く」「別の動画を再生したら PiP を止める」を実現する。
///
/// 再生位置・再生状態・スクラブ中の音声制御など、AVPlayer 自体の状態を反映するものは
/// ここに集約し、`iOSPlayer` は画面固有の UI 状態（コントロール表示・ジェスチャー・シート等）
/// だけを持つ。
@MainActor
@Observable
final class PlaybackModel {
    static let shared = PlaybackModel()

    let player = AVPlayer()
    let pip = PiPController()
    let seeker = SmoothSeeker()

    /// 再生位置・尺（`tick()` で 0.5 秒ごとに更新。スクラブ中は上書きしない）。
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = true
    /// 再生待ち（バッファ読み込み中）。true の間は呼び出し側でコントロールを隠す。
    var isWaiting = true
    /// シークバードラッグ中か（`tick()` の currentTime 上書きを止めるためのゲート）。
    var isScrubbing = false

    @ObservationIgnored private var scrubAudioActive = false
    @ObservationIgnored private var wasPlayingBeforeScrub = false
    // シーク中だけスタール待機を有効化し、再生が安定したら元（待たない＝即時再生）へ戻す予約。
    @ObservationIgnored private var restoreStallWaitingWhenPlaying = false

    @ObservationIgnored private let host: PlayerUIView
    @ObservationIgnored private var loadedKey: String?

    private init() {
        host = PlayerUIView(player: player)
        // 十分なバッファまで待つと、帯域が動画ビットレートに足りないとき再生が始まらない
        // （バッファ済みでも待ち続ける）。待たず即再生し、不足時はスタールしつつ進める。
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = true
        pip.setup(with: host.playerLayer)
        seeker.setPlayer(player)   // player 自体は不変（差し替わるのは currentItem）なので一度だけでよい
    }

    func hostView() -> PlayerUIView { host }

    /// 指定アイテムを読み込み再生する。別アイテムなら PiP を止めてから差し替える。
    /// - Returns: 再生可能なリソースがあれば true。
    @discardableResult
    func load(item: MediaItem, playInSilentMode: Bool) -> Bool {
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return false }
        AudioSessionManager.configure(playInSilentMode: playInSilentMode)
        // シーク中だけ有効化する待機設定が前アイテムから残らないよう、即時再生モードへ戻す。
        restoreStallWaitingWhenPlaying = false
        player.automaticallyWaitsToMinimizeStalling = false
        // 同一アイテムが既にロード済みなら継続（PiP から戻った場合など）。
        if loadedKey == item.id, player.currentItem != nil {
            player.play()
            isPlaying = true
            return true
        }
        if pip.isActive { pip.stop() }   // 別アイテム → 旧 PiP を停止
        player.replaceCurrentItem(with: PlayerItemFactory.make(url: url))
        loadedKey = item.id
        player.play()
        isPlaying = true
        return true
    }

    /// PiP 中でなければ一時停止する（一覧へ戻る時）。
    func pauseUnlessPiP() {
        guard !pip.isActive else { return }
        // PiP でないなら、抱えている AVPlayerItem（最大60秒バッファ＋ネットワークストリーム）を
        // 解放する。次に再生するとき load() で読み込み直す。
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedKey = nil
    }

    /// PiP 起動中なら停止する。
    func stopPiP() {
        if pip.isActive { pip.stop() }
    }

    /// 再生位置・状態の定期更新（`iOSPlayer` の Timer から 0.5 秒ごとに呼ばれる）。
    func tick() {
        if !isScrubbing {
            let t = player.currentTime().seconds
            if t.isFinite { currentTime = t }
        }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            duration = d
        }
        isPlaying = player.timeControlStatus == .playing
        isWaiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        // シーク後、再生が実際に再開して安定したら、元の即時再生モードへ戻す。
        if restoreStallWaitingWhenPlaying, player.timeControlStatus == .playing {
            player.automaticallyWaitsToMinimizeStalling = false
            restoreStallWaitingWhenPlaying = false
        }
    }

    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    /// 再生中なら一時停止する（シート/解析を開く前に呼ぶ）。
    func pausePlayback() {
        guard player.timeControlStatus != .paused else { return }
        player.pause()
        isPlaying = false
    }

    /// 現在の再生速度をプレイヤーへ反映する。再生中なら即時、停止中は次回 play() に反映。
    func applyPlaybackRate(_ rate: Double) {
        let r = Float(rate)
        player.defaultRate = r
        if player.timeControlStatus != .paused {
            player.rate = r
        }
    }

    /// シーク（スクラブ）開始: その位置の音を出すため再生状態にする。
    func beginScrub() {
        guard !scrubAudioActive else { return }
        scrubAudioActive = true
        wasPlayingBeforeScrub = (player.timeControlStatus == .playing)
        // ストリーミングではシーク先のバッファが空なので、待たない設定（即時再生）のままだと
        // シーク後に止まったまま自動再開しない。シーク中だけ「再生可能になるまで待つ」を許可する。
        restoreStallWaitingWhenPlaying = false
        player.automaticallyWaitsToMinimizeStalling = true
        player.play()
        isPlaying = true
    }

    /// シーク終了: 元の再生/停止状態へ戻す。
    func endScrub() {
        guard scrubAudioActive else { return }
        scrubAudioActive = false
        if !wasPlayingBeforeScrub {
            player.pause()
            isPlaying = false
            // 停止確定なら即、元の即時再生モードへ戻す。
            player.automaticallyWaitsToMinimizeStalling = false
        } else {
            // 再生継続。シーク先のバッファが溜まり再生が安定したら（tick で）即時再生モードへ戻す。
            restoreStallWaitingWhenPlaying = true
        }
    }
}

final class PlayerUIView: UIView {
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
