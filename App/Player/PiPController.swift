#if os(iOS)
import AVKit
import Observation

/// `AVPlayerLayer` を使った Picture in Picture の制御。
@MainActor
@Observable
final class PiPController: NSObject {
    /// PiP が起動中か。
    var isActive = false

    /// PiP 開始直前（再生カテゴリへ切替）／終了後（設定へ戻す）に呼ぶフック。
    @ObservationIgnored var onWillStart: (() -> Void)?
    @ObservationIgnored var onDidStop: (() -> Void)?

    @ObservationIgnored private var controller: AVPictureInPictureController?

    func setup(with layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported(), controller == nil else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
    }

    func start() {
        guard let controller else { return }
        onWillStart?()
        // セッション切替直後は不可のことがあるため少し待ってから開始。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            controller.startPictureInPicture()
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isActive = false
            self.onDidStop?()
        }
    }
}
#endif
