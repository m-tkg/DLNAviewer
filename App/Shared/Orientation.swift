#if os(iOS)
import UIKit

/// アプリの向きを制御するマネージャ。
///
/// 既定は全方向。プレイヤー表示中は全方向を許可し、一覧へ戻る時は確定的に縦へ戻す。
/// `AppDelegate.supportedInterfaceOrientationsFor` がこの `mask` を返すことで、
/// `requestGeometryUpdate` による強制回転（回転ロック中でも）を成立させる。
@MainActor
final class OrientationManager {
    static let shared = OrientationManager()

    var mask: UIInterfaceOrientationMask = .all

    private init() {}

    /// プレイヤー表示中：全方向許可（端末回転・強制回転を可能に）。
    func allowAll() {
        mask = .all
    }

    /// 指定の向きへ強制回転し、その向きにロックする（回転ロック中でも有効）。
    func force(_ orientation: UIInterfaceOrientationMask) {
        mask = orientation
        requestGeometry(orientation)
    }

    /// 一覧へ戻る時：確定的に縦へ戻す。
    func resetToPortrait() {
        mask = .portrait
        requestGeometry(.portrait)
    }

    /// 現在が横向きかどうか。
    var isLandscape: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.effectiveGeometry.interfaceOrientation.isLandscape ?? false
    }

    private func requestGeometry(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
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
