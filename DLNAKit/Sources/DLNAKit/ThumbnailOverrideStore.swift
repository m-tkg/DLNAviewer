import Foundation

/// 動画ごとの「サムネイルに使うシーンの時刻（秒）」を端末ローカルに永続化するストア。
/// キーは安定識別子（UPnP の object id 等）。
public final class ThumbnailOverrideStore: @unchecked Sendable {
    private let core: JSONStoreCore<[String: Double]>

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "thumbnailOverrides") {
        core = JSONStoreCore(storage: storage, key: key, default: { [:] })
    }

    /// 指定 ID のサムネイル時刻（未設定なら nil）。
    public func time(for id: String) -> Double? {
        core.read { $0[id] }
    }

    /// サムネイル時刻を設定する（nil で削除）。非有限値は無視。
    public func setTime(_ time: Double?, for id: String) {
        core.mutate { dict in
            if let time, time.isFinite, time >= 0 {
                dict[id] = time
            } else {
                dict[id] = nil
            }
        }
    }

    public func all() -> [String: Double] {
        core.read { $0 }
    }
}
