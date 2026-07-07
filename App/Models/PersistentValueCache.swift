import Foundation
import Observation
import DLNAKit

/// `MediaItem.persistentKey` をキーにした値のキャッシュ＋永続化を各モデル間で共通化するエンジン。
///
/// RatingsModel/BookmarksModel/TagsModel/ThumbnailsModel が個別に持っていた
/// `cache` 保持・`key(for:)`（旧スキーム移行）・永続化呼び出しの骨格を1箇所に集約する。
/// ドメイン固有のメソッド（`rating(for:)`・`add(_:for:)` 等）は各モデル側にそのまま残す。
@MainActor
@Observable
final class PersistentValueCache<Value> {
    private(set) var cache: [String: Value]
    private let persist: (Value?, String) -> Void

    init(cache: [String: Value], persist: @escaping (Value?, String) -> Void) {
        self.cache = cache
        self.persist = persist
    }

    /// ストアからキャッシュを読み直す（iCloud 同期反映用）。
    func reload(_ cache: [String: Value]) {
        self.cache = cache
    }

    /// 同一性キー。旧スキーム（タイトルのみ／object id）のデータが残っていれば一度だけ移行する。
    /// cache への書き込みは移行が起きたときだけ（参照だけで observable な変更を発生させない）。
    func key(for item: MediaItem) -> String {
        PersistentKeyMigration.key(for: item, lookup: { cache[$0] }) { value, key in
            cache[key] = value
            persist(value, key)
        }
    }

    func value(for item: MediaItem) -> Value? {
        cache[key(for: item)]
    }

    func setValue(_ value: Value?, for item: MediaItem) {
        set(value, forKey: key(for: item))
    }

    /// キー（安定識別子）を直接指定して読み書きする（タグの一括操作等、MediaItem を介さないケース用）。
    func set(_ value: Value?, forKey key: String) {
        cache[key] = value
        persist(value, key)
    }
}
