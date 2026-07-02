import Foundation

/// iCloud 同期対象の UserDefaults キー 1 件。
///
/// `reload` はリモート変更を取り込んだ後にモデルのキャッシュを再読込するためのフック。
/// `@AppStorage` のキーは UserDefaults の変更が SwiftUI に自動反映されるため nil でよい。
struct SyncedKey: Sendable {
    let key: String
    let reload: (@MainActor @Sendable () -> Void)?
}

/// 設定・評価・ブックマーク・手動サーバーを iCloud Key-Value Store で他デバイスと同期する。
///
/// 既存の `UserDefaults` 保存はそのままに、対象キーを iCloud とミラーする。
/// ダウンロード済みファイル等の大きいデータ・端末固有データは同期しない。
///
/// 同期対象キーを増やすときは `registry` に 1 エントリ追加するだけでよい
/// （ストアのキーなら対応モデルの `reload` も添える）。
final class CloudSync: NSObject, @unchecked Sendable {
    static let shared = CloudSync()

    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var applyingRemote = false
    private var started = false

    /// 同期対象キーの一覧（同期の唯一の定義箇所）。
    static let registry: [SyncedKey] = [
        // 設定（@AppStorage）
        SyncedKey(key: "seekUnitTop", reload: nil),
        SyncedKey(key: "seekUnitBottom", reload: nil),
        SyncedKey(key: "thumbnailSize", reload: nil),
        SyncedKey(key: "playInSilentMode", reload: nil),
        SyncedKey(key: "browseGridMode", reload: nil),
        SyncedKey(key: "filterLike", reload: nil),
        SyncedKey(key: "filterDislike", reload: nil),
        SyncedKey(key: "filterNone", reload: nil),
        // ストア（JSON Data。モデルのキャッシュ再読込が必要）
        SyncedKey(key: "manualServers", reload: { LibraryModel.shared.reload() }),
        SyncedKey(key: "videoRatings", reload: { RatingsModel.shared.reload() }),
        SyncedKey(key: "videoBookmarks", reload: { BookmarksModel.shared.reload() }),
        SyncedKey(key: "thumbnailOverrides", reload: { ThumbnailsModel.shared.reload() }),
        SyncedKey(key: "videoTags", reload: { TagsModel.shared.reload() }),
        SyncedKey(key: "favoriteFolders", reload: { FavoritesModel.shared.reload() }),
    ]

    /// 同期対象の UserDefaults キー。
    private let syncKeys = CloudSync.registry.map(\.key)

    /// 変更のあったキーに対応するモデルだけ再読込する。
    @MainActor
    static func reloadModels(changedKeys: [String]) {
        for entry in registry where changedKeys.contains(entry.key) {
            entry.reload?()
        }
    }

    /// 全モデルを再読込する（孤立データ掃除などストアを直接書き換えた後に使う）。
    @MainActor
    static func reloadAllModels() {
        for entry in registry {
            entry.reload?()
        }
    }

    /// メインスレッドから呼ぶ。
    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv)
        NotificationCenter.default.addObserver(
            self, selector: #selector(localChanged),
            name: UserDefaults.didChangeNotification, object: nil)
        kv.synchronize()
        // 初回: iCloud に値があれば取り込み、その後ローカルの現状を iCloud へ反映。
        pull(syncKeys)
        push(syncKeys)
    }

    @objc private func cloudChanged(_ note: Notification) {
        // 通知は任意スレッドで届くため、変更キーだけ取り出してメインで処理する。
        let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String])?
            .filter { syncKeys.contains($0) } ?? syncKeys
        guard !keys.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pull(keys)
            CloudSync.reloadModels(changedKeys: keys)
        }
    }

    @objc private func localChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.applyingRemote else { return }
            self.push(self.syncKeys)
        }
    }

    private func pull(_ keys: [String]) {
        applyingRemote = true
        defer { applyingRemote = false }
        for key in keys {
            if let value = kv.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    private func push(_ keys: [String]) {
        for key in keys {
            if let value = defaults.object(forKey: key) {
                kv.set(value, forKey: key)
            }
        }
        kv.synchronize()
    }
}
