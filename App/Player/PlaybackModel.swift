#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit
import DLNAKit

/// 再生（AVPlayer・PiP・描画レイヤー）を画面遷移より長く保持する永続モデル。
/// これにより「PiP のままリストへ戻っても再生が続く」「別の動画を再生したら PiP を止める」を実現する。
@MainActor
@Observable
final class PlaybackModel {
    static let shared = PlaybackModel()

    let player = AVPlayer()
    let pip = PiPController()

    @ObservationIgnored private let host: PlayerUIView
    @ObservationIgnored private var loadedKey: String?

    private init() {
        host = PlayerUIView(player: player)
        // 十分なバッファまで待つと、帯域が動画ビットレートに足りないとき再生が始まらない
        // （バッファ済みでも待ち続ける）。待たず即再生し、不足時はスタールしつつ進める。
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = true
        pip.setup(with: host.playerLayer)
    }

    func hostView() -> PlayerUIView { host }

    /// 指定アイテムを読み込み再生する。別アイテムなら PiP を止めてから差し替える。
    /// - Returns: 再生可能なリソースがあれば true。
    @discardableResult
    func load(item: MediaItem, playInSilentMode: Bool) -> Bool {
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return false }
        AudioSessionManager.configure(playInSilentMode: playInSilentMode)
        // 同一アイテムが既にロード済みなら継続（PiP から戻った場合など）。
        if loadedKey == item.id, player.currentItem != nil {
            player.play()
            return true
        }
        if pip.isActive { pip.stop() }   // 別アイテム → 旧 PiP を停止
        player.replaceCurrentItem(with: PlayerItemFactory.make(url: url))
        loadedKey = item.id
        player.play()
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
