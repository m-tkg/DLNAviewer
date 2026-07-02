import Foundation

/// 秒数の表示フォーマッタ（m:ss / h:mm:ss）。
/// PlayerView / BrowseView / SceneThumbnailView にあった 3 実装を統合したもの。
enum TimeFormatting {
    /// 秒数を `m:ss`（1 時間以上は `h:mm:ss`）にする。
    /// - Parameters:
    ///   - padHours: true なら 1 時間未満でも `h:mm:ss` にして桁を固定する
    ///     （総時間 1 時間超のとき現在時間の桁ぶれでシークバー幅が変わるのを防ぐ）。
    ///   - rounded: true なら四捨五入（一覧の総時間表示用）。false なら切り捨て（経過時間用）。
    static func timeString(_ seconds: Double, padHours: Bool = false, rounded: Bool = false) -> String {
        ""
    }
}
