import AVFoundation

/// 再生用 AVPlayerItem の生成（MacPlayer / PlaybackModel 共通）。
enum PlayerItemFactory {
    /// 数 GB・長尺動画の省メモリ・高速ロード設定で AVPlayerItem を作る。
    /// 精密タイミングを取得せずに開き（シークはキーフレーム単位になる）、
    /// 先読みは AVPlayer の自動管理に任せてメモリを抑える。
    static func make(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        return item
    }
}
