#if os(iOS)
import SwiftUI
import UIKit

/// プレイヤー中央のタッチ操作を UIKit の認識器でまとめて扱う透明レイヤー。
/// `UILongPressGestureRecognizer.numberOfTapsRequired = 1` が「ダブルタップして
/// 2 回目を離さず長押し」をそのまま表す。SwiftUI のジェスチャー合成では判定が
/// 安定しないため UIKit で実装し、`require(toFail:)` で各操作を明確に振り分ける。
struct GestureSurface: UIViewRepresentable {
    var onSingleTap: () -> Void
    var onDoubleTap: (_ forward: Bool) -> Void
    var onFastForwardStart: () -> Void
    var onFastForwardEnd: () -> Void
    var onMenu: () -> Void
    var onPanChanged: (_ translation: CGSize, _ startLocation: CGPoint, _ viewSize: CGSize) -> Void
    var onPanEnded: (_ translation: CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let c = context.coordinator

        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleSingle(_:)))
        single.numberOfTapsRequired = 1
        single.delegate = c

        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleDouble(_:)))
        double.numberOfTapsRequired = 2
        double.delegate = c

        // ダブルタップして 2 回目を離さず長押し → 2 倍速。
        let fast = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.handleFast(_:)))
        fast.numberOfTapsRequired = 1
        fast.minimumPressDuration = 0.25
        fast.delegate = c

        // 素の長押し → メニュー。
        let menu = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.handleMenu(_:)))
        menu.numberOfTapsRequired = 0
        menu.minimumPressDuration = 0.45
        menu.delegate = c

        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = c

        // 振り分け：シングルはダブル/長押しが不成立のときだけ。メニューはダブルタップ
        // 長押し（2倍速）やダブルタップ（スキップ）のときは出さない。
        single.require(toFail: double)
        single.require(toFail: fast)
        menu.require(toFail: fast)
        menu.require(toFail: double)

        [single, double, fast, menu, pan].forEach { view.addGestureRecognizer($0) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: GestureSurface
        private var panStart: CGPoint = .zero

        init(_ parent: GestureSurface) { self.parent = parent }

        @objc func handleSingle(_ g: UITapGestureRecognizer) { parent.onSingleTap() }

        @objc func handleDouble(_ g: UITapGestureRecognizer) {
            guard let view = g.view else { return }
            let x = g.location(in: view).x
            parent.onDoubleTap(x > view.bounds.width / 2)
        }

        @objc func handleFast(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began: parent.onFastForwardStart()
            case .ended, .cancelled, .failed: parent.onFastForwardEnd()
            default: break
            }
        }

        @objc func handleMenu(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { parent.onMenu() }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let t = g.translation(in: view)
            let translation = CGSize(width: t.x, height: t.y)
            switch g.state {
            case .began:
                panStart = g.location(in: view)
            case .changed:
                parent.onPanChanged(translation, panStart, view.bounds.size)
            case .ended, .cancelled, .failed:
                parent.onPanEnded(translation)
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
