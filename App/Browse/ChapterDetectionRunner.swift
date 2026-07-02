import Foundation
import Observation
import DLNAKit
#if canImport(UIKit)
import UIKit
#endif

/// 自動チャプター検出の実行管理。
/// 進捗の逐次反映・ブックマークへの逐次保存・キャンセル時のロールバック・
/// バックグラウンド実行猶予（iOS）を BrowseView から切り出したもの。
@MainActor
@Observable
final class ChapterDetectionRunner {
    /// 検出実行中か。
    private(set) var isRunning = false
    /// 実行中の進行状況（進捗・件数）。
    private(set) var run: ChapterRun?
    /// 完了・キャンセル時の結果メッセージ（alert 表示用。nil に戻すと閉じる）。
    var result: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// 自動チャプターを検出し、ブックマークとして逐次保存する。
    /// 進捗・件数はリアルタイム反映、キャンセル時は作成途中のチャプターを削除する。
    func detect(item: MediaItem) {
        guard !isRunning else { return }
        let run = ChapterRun()
        self.run = run
        isRunning = true

        // 別アプリへ切り替えても約30秒は処理を継続できるよう猶予を確保（iOS）。
        #if canImport(UIKit)
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ChapterDetect") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        #endif

        task = Task {
            let result = await ChapterDetector.detect(
                item: item,
                onProgress: { fraction in run.progress = fraction },
                onChapter: { time in
                    // 既存ブックマークと重複しない新規分だけ保存・記録（ロールバック対象）。
                    let existed = BookmarksModel.shared.bookmarks(for: item)
                        .contains { abs($0 - time) < 0.4 }
                    BookmarksModel.shared.add(time, for: item)
                    if !existed {
                        run.addedTimes.append(time)
                        run.count = run.addedTimes.count
                    }
                }
            )

            if result.cancelled || Task.isCancelled {
                // キャンセル: この実行で作成したチャプターを取り消す。
                for time in run.addedTimes {
                    BookmarksModel.shared.remove(time, for: item)
                }
                self.result = "キャンセルしました（作成途中の \(run.addedTimes.count) 個を削除）。"
            } else if run.addedTimes.isEmpty {
                self.result = "チャプターを検出できませんでした。"
            } else {
                let source = result.fromMetadata ? "埋め込みチャプター" : "シーン検出"
                self.result = "\(run.addedTimes.count) 個のチャプターをブックマークに保存しました（\(source)）。"
            }

            isRunning = false
            self.run = nil
            task = nil
            #if canImport(UIKit)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
            #endif
        }
    }

    /// 実行中の検出をキャンセルする（画面離脱時にも呼ぶ）。
    func cancel() {
        task?.cancel()
    }
}
