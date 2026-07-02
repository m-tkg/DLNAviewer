import Foundation

/// ハングしうる外部 API（AVFoundation のネットワーク越しアクセス等）を
/// 有限時間で必ず打ち切るための汎用ヘルパー。
enum AsyncTimeout {
    /// `operation` が `seconds` 秒以内に終わればその結果を返す。
    /// 間に合わなければ `onTimeout` を呼んで `nil` を返す（`operation` 自体のキャンセルは
    /// 呼び出し元が `onTimeout` の中で行うこと。例: `AVAssetImageGenerator.cancelAllCGImageGeneration()`）。
    static func run<T: Sendable>(
        seconds: Double,
        onTimeout: @escaping @Sendable () -> Void = {},
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                // operation が先に終わって cancelAll() されたら、ここは cancel error で抜ける
                // （その場合は本当のタイムアウトではないので onTimeout を呼ばない）。
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return nil
                }
                onTimeout()
                return nil
            }
            guard let result = await group.next() else { return nil }
            group.cancelAll()
            return result
        }
    }
}
