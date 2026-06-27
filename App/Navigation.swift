import Foundation
import DLNAKit

/// フォルダ階層をドリルダウンするためのナビゲーション値。
struct BrowseRoute: Hashable {
    var server: MediaServer
    var objectID: String
    var title: String
}

/// 再生画面へ遷移するためのナビゲーション値。
/// 同一フォルダ等の動画リストと開始位置を持ち、前/次の動画へ移動できる。
struct PlayerRoute: Hashable {
    var items: [MediaItem]
    var index: Int
}

/// トップ画面からの遷移先。
enum TopRoute: Hashable {
    case downloads
}

extension MediaItem {
    /// AVPlayer で再生しやすい `<res>` を優先的に選ぶ。
    /// mp4/mov/m4v/mpeg 系を優先し、無ければ先頭リソースにフォールバックする。
    var preferredVideoResource: MediaResource? {
        let preferredMIMEs = ["video/mp4", "video/quicktime", "video/x-m4v", "video/mpeg", "video/3gpp"]
        if let match = resources.first(where: { res in
            guard let mime = res.mimeType?.lowercased() else { return false }
            return preferredMIMEs.contains(mime)
        }) {
            return match
        }
        return resources.first
    }
}
