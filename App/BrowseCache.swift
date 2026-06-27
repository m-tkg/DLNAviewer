import Foundation
import DLNAKit

/// フォルダ（ContentDirectory）のブラウズ結果をセッション中メモリにキャッシュする。
/// キーは サーバー ID と objectID の組み合わせ。
@MainActor
final class BrowseCache {
    static let shared = BrowseCache()
    private var cache: [String: [DIDLObject]] = [:]

    private init() {}

    private func key(server: MediaServer, objectID: String) -> String {
        "\(server.id)|\(objectID)"
    }

    func objects(server: MediaServer, objectID: String) -> [DIDLObject]? {
        cache[key(server: server, objectID: objectID)]
    }

    func store(_ objects: [DIDLObject], server: MediaServer, objectID: String) {
        cache[key(server: server, objectID: objectID)] = objects
    }

    func invalidate(server: MediaServer, objectID: String) {
        cache[key(server: server, objectID: objectID)] = nil
    }
}
