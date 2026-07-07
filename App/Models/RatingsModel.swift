import Foundation
import Observation
import DLNAKit

/// 動画評価を保持・更新する ViewModel（端末ローカル永続化）。
/// 環境経由で BrowseView / PlayerView から共有する。
@MainActor
@Observable
final class RatingsModel {
    static let shared = RatingsModel()
    private let store: RatingStore
    private let cache: PersistentValueCache<Rating>
    private let feedback: FeedbackCenter

    init(store: RatingStore = RatingStore(), feedback: FeedbackCenter = .shared) {
        self.store = store
        self.feedback = feedback
        self.cache = PersistentValueCache(cache: store.all()) { value, key in
            store.setRating(value ?? .none, for: key)
        }
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache.reload(store.all())
    }

    func rating(for item: MediaItem) -> Rating {
        cache.value(for: item) ?? .none
    }

    func set(_ rating: Rating, for item: MediaItem) {
        cache.setValue(rating == .none ? nil : rating, for: item)
        feedback.flash(rating)   // 中央にアイコン演出
    }
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
