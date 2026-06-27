import Foundation
import Observation
import DLNAKit

/// 動画評価を保持・更新する ViewModel（端末ローカル永続化）。
/// 環境経由で BrowseView / PlayerView から共有する。
@MainActor
@Observable
final class RatingsModel {
    private var cache: [String: Rating]
    private let store: RatingStore

    init(store: RatingStore = RatingStore()) {
        self.store = store
        self.cache = store.all()
    }

    func rating(for item: MediaItem) -> Rating {
        cache[item.ratingKey] ?? .none
    }

    func set(_ rating: Rating, for item: MediaItem) {
        if rating == .none {
            cache[item.ratingKey] = nil
        } else {
            cache[item.ratingKey] = rating
        }
        store.setRating(rating, for: item.ratingKey)
    }
}

extension MediaItem {
    /// 評価の保存キー。UPnP の object id は IP 変化に影響されず安定。
    var ratingKey: String { id }
}

extension Rating {
    /// 一覧・メニューで使う SF Symbol。
    var symbol: String {
        switch self {
        case .like: return "hand.thumbsup.fill"
        case .dislike: return "hand.thumbsdown.fill"
        case .none: return "hand.thumbsup"
        }
    }

    var label: String {
        switch self {
        case .like: return "Like"
        case .dislike: return "Dislike"
        case .none: return "評価なし"
        }
    }
}
