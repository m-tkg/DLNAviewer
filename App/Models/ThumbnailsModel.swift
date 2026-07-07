import Foundation
import Observation
import DLNAKit

/// 動画ごとの「サムネイルに使うシーンの時刻」を保持・更新する。端末ローカル永続化＋iCloud 同期対象。
@MainActor
@Observable
final class ThumbnailsModel {
    static let shared = ThumbnailsModel()
    private let store: ThumbnailOverrideStore
    private let cache: PersistentValueCache<Double>

    init(store: ThumbnailOverrideStore = ThumbnailOverrideStore()) {
        self.store = store
        self.cache = PersistentValueCache(cache: store.all()) { value, key in
            store.setTime(value, for: key)
        }
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache.reload(store.all())
    }

    /// サムネイルに使う時刻（未設定なら nil）。
    func time(for item: MediaItem) -> Double? {
        cache.value(for: item)
    }

    /// このシーンの時刻をサムネイルに設定する。
    func set(_ time: Double, for item: MediaItem) {
        guard time.isFinite, time >= 0 else { return }
        cache.setValue(time, for: item)
    }

    func clear(for item: MediaItem) {
        cache.setValue(nil, for: item)
    }
}
