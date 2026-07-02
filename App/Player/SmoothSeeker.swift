#if os(iOS)
import AVFoundation

/// スクラブ中に連続するシーク要求を「最新の目標位置を追いかける」形で滑らかに処理する。
/// 同時に走るシークは 1 つだけにし、新しい目標が来たら完了後に追従する。
@MainActor
final class SmoothSeeker {
    private weak var player: AVPlayer?
    private var isSeeking = false
    private var chaseTime: CMTime = .invalid
    private var chaseTolerance: CMTime = .zero

    func setPlayer(_ player: AVPlayer) { self.player = player }

    func seek(toSeconds seconds: Double, tolerance: Double) {
        chaseTime = CMTime(seconds: seconds, preferredTimescale: 600)
        chaseTolerance = CMTime(seconds: tolerance, preferredTimescale: 600)
        if !isSeeking { step() }
    }

    private func step() {
        guard let player, chaseTime.isValid else { isSeeking = false; return }
        isSeeking = true
        let target = chaseTime
        let tol = chaseTolerance
        player.seek(to: target, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            Task { @MainActor in self?.finished(target) }
        }
    }

    private func finished(_ target: CMTime) {
        if chaseTime == target {
            isSeeking = false
        } else {
            step()   // ドラッグ中に新しい目標が来ていれば追従
        }
    }
}
#endif
