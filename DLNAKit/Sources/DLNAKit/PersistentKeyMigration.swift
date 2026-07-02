import Foundation

/// 動画ごとの永続データを `MediaItem.persistentKey` で引くときの共通ヘルパ。
///
/// 旧スキーム（タイトルのみ／object id）で保存されたデータが残っていれば、
/// 新キーへ一度だけ移行する。App 側の各モデル（評価・ブックマーク・タグ・サムネ上書き）が
/// 同じロジックをコピペしていたのを集約したもの。
public enum PersistentKeyMigration {
    /// `item` の保存キーを返す。`lookup(新キー)` が nil なら `legacyPersistentKeys` を
    /// 順に探し、最初に見つかった値を `migrate(値, 新キー)` へ渡す（キャッシュ更新と
    /// ストア書き込みは呼び出し側の責務）。旧キーのレコードは削除しない。
    ///
    /// 参照は `lookup` クロージャ経由の読み取りのみで、書き込みは実際に移行が起きた
    /// ときだけ `migrate` で行う。@Observable モデルのキャッシュを inout で受けると
    /// 変更が無くても Observation 上は「書き込み」となり、View body からの参照が
    /// 自分自身を無効化して無限再描画ループになるため、この形を崩さないこと。
    public static func key<Value>(
        for item: MediaItem,
        lookup: (String) -> Value?,
        migrate: (Value, String) -> Void
    ) -> String {
        let key = item.persistentKey
        guard lookup(key) == nil else { return key }
        for legacy in item.legacyPersistentKeys where legacy != key {
            if let value = lookup(legacy) {
                migrate(value, key)
                break
            }
        }
        return key
    }
}
