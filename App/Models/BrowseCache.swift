import Foundation
import DLNAKit

/// フォルダ（ContentDirectory）のブラウズ結果をセッション中メモリにキャッシュする。
/// キーは サーバー ID と objectID の組み合わせ。
/// 有効期限（TTL）を設け、サーバー側のデータ入れ替えに古い一覧が残り続けないようにする。
@MainActor
final class BrowseCache {
    static let shared = BrowseCache()

    private struct Entry {
        let objects: [DIDLObject]
        let time: Date
    }
    private var cache: [String: Entry] = [:]
    /// この時間を超えたキャッシュは無効として取り直す（サーバー入れ替えへの追従）。
    private let ttl: TimeInterval = 120

    /// 通常は `shared` を使う。テストでは独立したインスタンスを作れる。
    init() {}

    private func key(server: MediaServer, objectID: String) -> String {
        "\(server.id)|\(objectID)"
    }

    func objects(server: MediaServer, objectID: String) -> [DIDLObject]? {
        let k = key(server: server, objectID: objectID)
        guard let entry = cache[k] else { return nil }
        if Date().timeIntervalSince(entry.time) > ttl {
            cache[k] = nil
            return nil
        }
        return entry.objects
    }

    func store(_ objects: [DIDLObject], server: MediaServer, objectID: String) {
        cache[key(server: server, objectID: objectID)] = Entry(objects: objects, time: Date())
    }

    func invalidate(server: MediaServer, objectID: String) {
        cache[key(server: server, objectID: objectID)] = nil
    }

    func clearAll() {
        cache.removeAll()
    }
}
