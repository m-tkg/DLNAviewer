import Foundation
import Testing
@testable import DLNAviewer

@Suite("CloudSync.registry")
struct CloudSyncRegistryTests {
    @Test("キーに重複がない")
    func noDuplicateKeys() {
        let keys = CloudSync.registry.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("ストアの 6 キーすべてに reload が設定されている")
    func storeKeysHaveReload() {
        let storeKeys: Set<String> = [
            "manualServers", "videoRatings", "videoBookmarks",
            "thumbnailOverrides", "videoTags", "favoriteFolders",
        ]
        for entry in CloudSync.registry where storeKeys.contains(entry.key) {
            #expect(entry.reload != nil, "\(entry.key) に reload が無い")
        }
        let registered = Set(CloudSync.registry.map(\.key))
        #expect(storeKeys.isSubset(of: registered), "ストアキーがレジストリから漏れている")
    }

    @Test("プレイヤー設定 skipSeconds / doubleTapSeconds / playbackRate が同期対象に含まれる")
    func playerSettingsAreSynced() {
        let registered = Set(CloudSync.registry.map(\.key))
        for key in ["skipSeconds", "doubleTapSeconds", "playbackRate"] {
            #expect(registered.contains(key), "\(key) が同期対象から漏れている")
        }
    }
}
