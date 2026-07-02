import Foundation

/// 動画ごとの永続データを `MediaItem.persistentKey` で引くときの共通ヘルパ。
///
/// 旧スキーム（タイトルのみ／object id）で保存されたデータが残っていれば、
/// 新キーへ一度だけ移行する。App 側の各モデル（評価・ブックマーク・タグ・サムネ上書き）が
/// 同じロジックをコピペしていたのを集約したもの。
public enum PersistentKeyMigration {
    /// `item` の保存キーを返す。`cache` に新キーの値が無ければ `legacyPersistentKeys` を
    /// 順に探し、最初に見つかった値を新キーへ移行（`cache` 更新＋`persist` でストアへ書き込み）する。
    /// 旧キーのレコードは削除しない（他モデルとの互換のため現行挙動を踏襲）。
    public static func key<Value>(
        for item: MediaItem,
        cache: inout [String: Value],
        persist: (Value, String) -> Void
    ) -> String {
        item.persistentKey
    }
}
