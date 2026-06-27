import Foundation

extension Notification.Name {
    /// iCloud から他デバイスの変更を取り込んだ時に通知する。
    static let cloudSyncDidUpdate = Notification.Name("CloudSyncDidUpdate")
}

/// 設定・評価・ブックマーク・手動サーバーを iCloud Key-Value Store で他デバイスと同期する。
///
/// 既存の `UserDefaults` 保存はそのままに、対象キーを iCloud とミラーする。
/// ダウンロード済みファイル等の大きいデータ・端末固有データは同期しない。
final class CloudSync: NSObject, @unchecked Sendable {
    static let shared = CloudSync()

    private let kv = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var applyingRemote = false
    private var started = false

    /// 同期対象の UserDefaults キー。
    private let syncKeys = [
        // 設定（@AppStorage）
        "seekUnitTop", "seekUnitBottom", "thumbnailSize", "playInSilentMode",
        "browseGridMode", "filterLike", "filterDislike", "filterNone",
        // ストア（JSON Data）
        "manualServers", "videoRatings", "videoBookmarks", "thumbnailOverrides", "videoTags",
    ]

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
        DispatchQueue.main.async { [weak self] in
            guard let self, !keys.isEmpty else { return }
            self.pull(keys)
            NotificationCenter.default.post(name: .cloudSyncDidUpdate, object: nil)
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
