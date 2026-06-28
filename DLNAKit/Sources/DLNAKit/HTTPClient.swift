import Foundation

/// 一時的なネットワークエラーかを判定する。
public enum HTTPRetry {
    /// リトライする価値のある一時的・接続系の `URLError` か。
    public static func isRetriable(_ error: Error) -> Bool {
        // TODO: 実装する（現在はスタブ）。
        false
    }
}

/// DLNA サーバーへの HTTP アクセス用の共有セッションとリトライ。
///
/// `URLSession.shared` は経路変化・スリープ復帰の後に古い接続状態を保持し、実際には
/// 接続できるのに `-1009`(notConnectedToInternet) 等を返すことがある（アプリ再起動で回復）。
/// それを避けるため `waitsForConnectivity` を有効にした専用セッションを使い、接続系エラーは
/// 短い遅延を挟んで数回リトライする。
public enum DLNAHTTP {
    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
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
