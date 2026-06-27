import Foundation
import Observation
import DLNAKit

/// 動画ごとの「サムネイルに使うシーンの時刻」を保持・更新する。端末ローカル永続化＋iCloud 同期対象。
@MainActor
@Observable
final class ThumbnailsModel {
    static let shared = ThumbnailsModel()

    private var cache: [String: Double]
    private let store: ThumbnailOverrideStore

    init(store: ThumbnailOverrideStore = ThumbnailOverrideStore()) {
        self.store = store
        self.cache = store.all()
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload() {
        cache = store.all()
    }

    /// サムネイルに使う時刻（未設定なら nil）。
    func time(for item: MediaItem) -> Double? {
        cache[item.id]
    }

    /// このシーンの時刻をサムネイルに設定する。
    func set(_ time: Double, for item: MediaItem) {
        guard time.isFinite, time >= 0 else { return }
        cache[item.id] = time
        store.setTime(time, for: item.id)
    }

    func clear(for item: MediaItem) {
        cache[item.id] = nil
        store.setTime(nil, for: item.id)
    }
}
