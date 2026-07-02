import Foundation
import Testing
import DLNAKit
@testable import DLNAviewer

/// テスト用のフェイクブラウザ。objectID → 子要素の静的ツリーを返す。
private struct FakeBrowser: ContentBrowsing {
    var tree: [String: [DIDLObject]] = [:]
    var titles: [String: String] = [:]

    func browseChildren(controlURL: URL, objectID: String) async throws -> [DIDLObject] {
        guard let children = tree[objectID] else { throw URLError(.badServerResponse) }
        return children
    }

    func metadataTitle(controlURL: URL, objectID: String) async throws -> String? {
        titles[objectID]
    }
}

private func folder(_ id: String, title: String) -> DIDLObject {
    .container(MediaContainer(id: id, parentID: "0", title: title, childCount: 0))
}

private func video(_ id: String, title: String) -> DIDLObject {
    .item(MediaItem(id: id, parentID: "0", title: title,
                    upnpClass: "object.item.videoItem",
                    resources: [MediaResource(url: URL(string: "http://x/\(id)")!)]))
}

private let server = MediaServer(
    id: "uuid:test", friendlyName: "NAS",
    descriptionURL: URL(string: "http://nas/desc.xml")!,
    contentDirectoryControlURL: URL(string: "http://nas/control")!,
    origin: .manual
)

@MainActor
@Suite("BrowseViewModel")
struct BrowseViewModelTests {
    private func makeModel(objectID: String = "0", path: [String] = [],
                           resolveByPath: Bool = false,
                           browser: FakeBrowser) -> BrowseViewModel {
        BrowseViewModel(server: server, objectID: objectID, title: path.last ?? "root",
                        path: path, resolveByPath: resolveByPath, downloadsMode: false,
                        client: browser, cache: BrowseCache())
    }

    @Test("通常のフォルダを読み込める")
    func loadsFolder() async {
        let browser = FakeBrowser(tree: ["10": [video("a", title: "A.mp4")]])
        let model = makeModel(objectID: "10", browser: browser)
        await model.load()
        #expect(model.error == nil)
        #expect(model.objects.map(\.title) == ["A.mp4"])
        #expect(!model.isLoading)
    }

    @Test("お気に入り: 保存パスで objectID を再解決する（サーバー入れ替え対応）")
    func resolvesByPath() async {
        // ルート → "Movies"(id 新: 99) → 中身。保存時の objectID とは違う id でも名前で辿れる。
        let browser = FakeBrowser(tree: [
            "0": [folder("99", title: "Movies"), folder("50", title: "Music")],
            "99": [video("v", title: "V.mp4")],
        ])
        let model = makeModel(objectID: "old-id", path: ["Movies"], resolveByPath: true, browser: browser)
        await model.load()
        #expect(model.error == nil)
        #expect(model.objects.map(\.title) == ["V.mp4"])
    }

    @Test("お気に入り: パスの途中のフォルダが消えていたらエラー（誤フォルダを開かない）")
    func pathNotFoundShowsError() async {
        let browser = FakeBrowser(tree: ["0": [folder("50", title: "Music")]])
        let model = makeModel(objectID: "old-id", path: ["Movies"], resolveByPath: true, browser: browser)
        await model.load()
        #expect(model.error != nil)
        #expect(model.objects.isEmpty)
    }

    @Test("旧お気に入り（パスなし）: フォルダ名が一致すれば objectID で開く")
    func legacyFavoriteOpensWhenTitleMatches() async {
        var browser = FakeBrowser(tree: ["42": [video("v", title: "V.mp4")]])
        browser.titles["42"] = "root"   // makeModel の title は path.last ?? "root"
        let model = makeModel(objectID: "42", resolveByPath: true, browser: browser)
        await model.load()
        #expect(model.error == nil)
        #expect(model.objects.map(\.title) == ["V.mp4"])
    }

    @Test("旧お気に入り（パスなし）: フォルダ名が変わっていたらエラー")
    func legacyFavoriteRejectsRenamedFolder() async {
        var browser = FakeBrowser(tree: ["42": [video("v", title: "V.mp4")]])
        browser.titles["42"] = "別のフォルダ"
        let model = makeModel(objectID: "42", resolveByPath: true, browser: browser)
        await model.load()
        #expect(model.error != nil)
    }

    @Test("2 回目の load はキャッシュを使い、force で取り直す")
    func usesCacheUnlessForced() async {
        let cache = BrowseCache()
        var browser = FakeBrowser(tree: ["10": [video("a", title: "A.mp4")]])
        let model = BrowseViewModel(server: server, objectID: "10", title: "t", path: [],
                                    resolveByPath: false, downloadsMode: false,
                                    client: browser, cache: cache)
        await model.load()
        #expect(model.objects.count == 1)

        // サーバー側が変わってもキャッシュ有効中は古い一覧のまま。
        cache.store([video("a", title: "A.mp4"), video("b", title: "B.mp4")], server: server, objectID: "10")
        await model.load()
        #expect(model.objects.count == 2, "キャッシュから読む")

        browser.tree["10"] = [video("c", title: "C.mp4")]
        let model2 = BrowseViewModel(server: server, objectID: "10", title: "t", path: [],
                                     resolveByPath: false, downloadsMode: false,
                                     client: browser, cache: cache)
        await model2.load(force: true)
        #expect(model2.objects.map(\.title) == ["C.mp4"], "force はキャッシュを無視する")
    }
}
