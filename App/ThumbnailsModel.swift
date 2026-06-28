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
        cache[key(for: item)]
    }

    /// このシーンの時刻をサムネイルに設定する。
    func set(_ time: Double, for item: MediaItem) {
        guard time.isFinite, time >= 0 else { return }
        let k = key(for: item)
        cache[k] = time
        store.setTime(time, for: k)
    }

    func clear(for item: MediaItem) {
        let k = key(for: item)
        cache[k] = nil
        store.setTime(nil, for: k)
    }

    /// 同一性キー。旧スキーム（タイトルのみ／object id）のデータが残っていれば一度だけ移行する。
    private func key(for item: MediaItem) -> String {
        let key = item.persistentKey
        guard cache[key] == nil else { return key }
        for legacy in item.legacyPersistentKeys where legacy != key {
            if let value = cache[legacy] {
                cache[key] = value
                store.setTime(value, for: key)
                break
            }
        }
        return key
    }
}
