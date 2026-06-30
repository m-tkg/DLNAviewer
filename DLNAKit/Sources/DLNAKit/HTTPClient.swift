import Foundation

/// 一時的なネットワークエラーかを判定する。
public enum HTTPRetry {
    /// リトライする価値のある一時的・接続系の `URLError` か。
    public static func isRetriable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,   // -1009
             .networkConnectionLost,     // -1005
             .timedOut,                  // -1001
             .cannotConnectToHost,       // -1004
             .cannotFindHost,            // -1003
             .dnsLookupFailed:           // -1006
            return true
        default:
            return false
        }
    }
}

/// DLNA サーバーへの HTTP アクセス用の共有セッションとリトライ。
///
/// `URLSession.shared` は経路変化・スリープ復帰の後に古い接続状態を保持し、実際には
/// 接続できるのに `-1009`(notConnectedToInternet) 等を返すことがある（アプリ再起動で回復）。
/// それを避けるため `waitsForConnectivity` を有効にした専用セッションを使い、接続系エラーは
/// 短い遅延を挟んで数回リトライする。
public enum DLNAHTTP {
    /// 端末非依存の汎用 UPnP コントロールポイントを名乗る User-Agent。
    public static let userAgent = "DLNAviewer/1.0 UPnP/1.0"

    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 到達不能なサーバで長時間ブロックしないよう、接続回復は待たず短めの上限にする
        // （一時的な不通はリトライ＋呼び出し側の並行化で吸収する）。
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        // デバイス記述・SOAP Browse は常に最新を取得する。標準の URLCache を使うと、
        // NAS の再起動中に一度返った壊れた応答（HTML エラーページ等）がヒューリスティック
        // にキャッシュされ、以後そのサーバの解析が固着し続けることがあるため無効化する。
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // User-Agent を端末非依存の汎用 UPnP クライアントに固定する。一部の DLNA サーバーは
        // クライアントの User-Agent（既定では iPhone/iPad など端末名を含む）で応答を出し分け、
        // 特定端末にだけ壊れた/別構造の記述を返すことがあるため、両端末で同じ応答を引かせる。
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    /// リトライ付き `data(for:)`。接続系エラー時に最大 `retries` 回まで再試行する。
    public static func data(for request: URLRequest, retries: Int = 2) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                return try await session.data(for: request)
            } catch {
                attempt += 1
                guard HTTPRetry.isRetriable(error), attempt <= retries else { throw error }
                // 軽い線形バックオフ（300ms, 600ms, …）。
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 300_000_000)
            }
        }
    }

    /// リトライ付き `data(from:)`。
    public static func data(from url: URL, retries: Int = 2) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url), retries: retries)
    }
}
