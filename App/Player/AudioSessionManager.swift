#if os(iOS)
import AVFoundation

/// オーディオセッションのカテゴリを切り替える。
/// `.playback` はサイレントスイッチを無視して再生、`.ambient` はサイレント時にミュートされる。
enum AudioSessionManager {
    static func configure(playInSilentMode: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if playInSilentMode {
                try session.setCategory(.playback, mode: .moviePlayback)
            } else {
                try session.setCategory(.ambient)
            }
            try session.setActive(true)
        } catch {
            // 設定失敗時は既定の挙動にフォールバック。
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
