import Foundation

/// 動画への評価。
public enum Rating: String, Codable, Sendable, CaseIterable {
    case none
    case like
    case dislike
}

/// 動画の評価を端末ローカルに永続化するストア。
///
/// キーは安定識別子（UPnP の object id 等）。
public final class RatingStore: @unchecked Sendable {
    private let core: JSONStoreCore<[String: Rating]>

    public init(storage: KeyValueStorage = UserDefaults.standard, key: String = "videoRatings") {
        core = JSONStoreCore(storage: storage, key: key, default: { [:] })
    }

    /// 指定 ID の評価（未設定なら `.none`）。
    public func rating(for id: String) -> Rating {
        core.read { $0[id] ?? .none }
    }

    /// 評価を設定する。`.none` の場合はレコードを削除する。
    public func setRating(_ rating: Rating, for id: String) {
        core.mutate { dict in
            dict[id] = rating == .none ? nil : rating
        }
    }

    /// 保存済みの全評価。
    public func all() -> [String: Rating] {
        core.read { $0 }
    }
}
