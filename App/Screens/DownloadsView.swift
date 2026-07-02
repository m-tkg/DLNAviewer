import SwiftUI

/// ダウンロード済みの動画一覧。
/// ファイルリスト（BrowseView）と同じ仕様（検索・タグ/ブックマーク絞り込み・評価フィルタ・
/// リスト/グリッド・長押しメニュー・自動チャプター等）をダウンロード一覧モードで再利用する。
struct DownloadsView: View {
    var body: some View {
        BrowseView(title: "ダウンロード済み", downloadsMode: true)
    }
}
