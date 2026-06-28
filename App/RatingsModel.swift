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

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache = store.all()
    }

    func rating(for item: MediaItem) -> Rating {
        cache[key(for: item)] ?? .none
    }

    func set(_ rating: Rating, for item: MediaItem) {
        let k = key(for: item)
        cache[k] = (rating == .none) ? nil : rating
        store.setRating(rating, for: k)
        FeedbackCenter.shared.flash(rating)   // 中央にアイコン演出
    }

    /// 同一性キー。旧スキーム（タイトルのみ／object id）のデータが残っていれば一度だけ移行する。
    private func key(for item: MediaItem) -> String {
        let key = item.persistentKey
        guard cache[key] == nil else { return key }
        for legacy in item.legacyPersistentKeys where legacy != key {
            if let value = cache[legacy] {
                cache[key] = value
                store.setRating(value, for: key)
                break
            }
        }
        return key
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
