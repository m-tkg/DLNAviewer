#if os(iOS)
import UIKit

/// 端末の回転ロック中でも、アプリ側から強制的に向きを変えるためのマネージャ。
///
/// `AppDelegate.supportedInterfaceOrientationsFor` がこの `mask` を返すことで、
/// `requestGeometryUpdate` による強制回転を成立させる。
@MainActor
final class OrientationManager {
    static let shared = OrientationManager()

    /// 現在アプリが許可する向き。既定は全方向（通常どおり）。
    var mask: UIInterfaceOrientationMask = .all

    private init() {}

    /// 指定の向きへ強制回転し、その向きにロックする。
    func force(_ orientation: UIInterfaceOrientationMask) {
        mask = orientation
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// ロックを解除して全方向に戻す。
    func unlock() {
        mask = .all
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// 現在が横向きかどうか。
    var isLandscape: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.effectiveGeometry.interfaceOrientation.isLandscape ?? false
    }
}

/// `supportedInterfaceOrientations` を `OrientationManager` に委譲する AppDelegate。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // UIKit はこのコールバックをメインスレッドで呼ぶ。
        MainActor.assumeIsolated { OrientationManager.shared.mask }
    }
}
#endif
