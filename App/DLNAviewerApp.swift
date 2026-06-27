import SwiftUI

@main
struct DLNAviewerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some Scene {
        WindowGroup {
            ServerListView()
                // 評価変更時の中央アイコン演出（当たり判定なし）。
                .overlay { RatingFeedbackOverlay() }
            #if os(iOS)
                // タスクスイッチャー（非アクティブ時のスナップショット）で中身を隠す。
                .overlay {
                    if scenePhase != .active {
                        PrivacyCover()
                    }
                }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 640)
        #endif
    }
}

#if os(iOS)
/// タスクスイッチャーのプライバシー用カバー。
private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("DLNAviewer")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}
#endif
