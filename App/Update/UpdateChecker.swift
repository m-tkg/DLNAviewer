#if os(macOS)
import Foundation
import Observation
import DLNAKit

/// 設定画面のアップデート UI を駆動する状態モデル。
@MainActor
@Observable
final class UpdateChecker {
    /// 起動時の自動チェック（`ServerListView`）と設定画面の手動操作（`SettingsView`）で
    /// 状態を一元化するため共有する。
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case failed(String)
    }

    private(set) var state: State = .idle
    /// 起動時の自動チェックで新版が見つかったときのみセットする確認ダイアログ提示用。
    /// 手動チェック（`check`）ではセットしない。
    private(set) var launchPrompt: ReleaseInfo?
    let currentVersion = UpdateService.currentVersion
    private let service = UpdateService()
    /// 起動時チェックはアプリ起動につき一度きり（ウィンドウ再表示等で多重実行しない）。
    private var didLaunchCheck = false

    /// アプリ起動時に一度だけ呼ぶサイレントチェック。新版があれば `state` を `.available` にし、
    /// 確認ダイアログ提示用の `launchPrompt` をセットする。最新時・失敗時は何も提示しない
    /// （失敗は設定画面の手動チェックでエラー表示する）。
    func checkOnLaunch() async {
        guard !didLaunchCheck else { return }
        didLaunchCheck = true
        // 起動直後より前にユーザーが手動チェックを始めていたら邪魔しない。
        guard case .idle = state else { return }
        do {
            let release = try await service.fetchLatestRelease()
            if VersionComparator.isNewer(tag: release.tagName, than: currentVersion) {
                state = .available(release)
                launchPrompt = release
            }
        } catch {
            // 起動時は静かに失敗する。
        }
    }

    /// 起動時確認ダイアログを閉じる（「後で」選択時、または更新開始時）。
    func dismissLaunchPrompt() {
        launchPrompt = nil
    }

    /// 最新リリースを確認し、現在より新しければ `.available` にする。
    func check() async {
        state = .checking
        do {
            let release = try await service.fetchLatestRelease()
            if VersionComparator.isNewer(tag: release.tagName, than: currentVersion) {
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// ダウンロード→入れ替え→再起動。成功時はアプリが終了する。
    func update(to release: ReleaseInfo) async {
        state = .downloading
        do {
            try await SelfUpdater.performUpdate(release, service: service)
            // 成功すると NSApp.terminate されるためここには戻らない。
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
#endif
