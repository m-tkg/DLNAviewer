import Foundation
import Observation
import DLNAKit

/// `BrowseViewModel` が使うブラウズ機能の最小面（テスト時にフェイクへ差し替え）。
protocol ContentBrowsing: Sendable {
    /// 直下の子オブジェクトを全件取得する。
    func browseChildren(controlURL: URL, objectID: String) async throws -> [DIDLObject]
    /// objectID 自身のメタデータからタイトルを取得する。
    func metadataTitle(controlURL: URL, objectID: String) async throws -> String?
}

extension ContentDirectoryClient: ContentBrowsing {
    func browseChildren(controlURL: URL, objectID: String) async throws -> [DIDLObject] {
        try await browseAll(controlURL: controlURL, objectID: objectID)
    }

    func metadataTitle(controlURL: URL, objectID: String) async throws -> String? {
        let result = try await browse(controlURL: controlURL, objectID: objectID, browseFlag: .metadata)
        switch result.objects.first {
        case .container(let c): return c.title
        case .item(let i): return i.title
        case nil: return nil
        }
    }
}

/// フォルダの読み込み・お気に入りパスの再解決・キャッシュ制御を担う
/// BrowseView の ViewModel。表示用フィルタは `BrowseFilter`、描画は View 側。
@MainActor
@Observable
final class BrowseViewModel {
    let server: MediaServer?
    let objectID: String
    let title: String
    let path: [String]
    let resolveByPath: Bool
    let downloadsMode: Bool

    private(set) var objects: [DIDLObject] = []
    private(set) var isLoading = true
    private(set) var error: String?

    /// お気に入りからパス再解決した実際の objectID（未解決なら nil で objectID を使う）。
    @ObservationIgnored private var effectiveObjectID: String?
    @ObservationIgnored private let client: ContentBrowsing
    @ObservationIgnored private let cache: BrowseCache

    init(
        server: MediaServer?,
        objectID: String,
        title: String,
        path: [String],
        resolveByPath: Bool,
        downloadsMode: Bool,
        client: ContentBrowsing = ContentDirectoryClient(),
        cache: BrowseCache = .shared
    ) {
        self.server = server
        self.objectID = objectID
        self.title = title
        self.path = path
        self.resolveByPath = resolveByPath
        self.downloadsMode = downloadsMode
        self.client = client
        self.cache = cache
    }

    /// フォルダの中身を読み込む。`force == false` ならキャッシュを使う。
    func load(force: Bool = false) async {
        // ダウンロード一覧モードは取得不要（View がローカルの一覧を直接参照する）。
        if downloadsMode {
            isLoading = false
            error = nil
            return
        }
        guard let server else { isLoading = false; return }
        guard let controlURL = server.contentDirectoryControlURL else {
            error = "ContentDirectory が見つかりません"
            isLoading = false
            return
        }
        // お気に入りから開いた場合、保存パスで objectID を再解決する（サーバー入れ替え対応）。
        // 一度解決したら effectiveObjectID にキャッシュし、以降はそれを使う。
        let oid: String
        if let resolved = effectiveObjectID {
            oid = resolved
        } else if resolveByPath {
            isLoading = true
            let notFound = "お気に入りのフォルダが見つかりません。サーバー側で削除・変更された可能性があります（再登録すると追従します）。"
            if !path.isEmpty {
                // 再登録済み（パスあり）: 名前パスで辿る。辿れなければ誤フォルダを開かずエラー。
                guard let resolved = await resolvePath(controlURL: controlURL) else {
                    error = notFound; isLoading = false; return
                }
                oid = resolved
            } else {
                // 旧データ（パスなし）: objectID で開くが、フォルダ名が保存名と一致するか確認する。
                guard let name = try? await client.metadataTitle(controlURL: controlURL, objectID: objectID),
                      name == title else {
                    error = notFound; isLoading = false; return
                }
                oid = objectID
            }
            effectiveObjectID = oid
        } else {
            oid = objectID
        }
        // キャッシュ利用（再読み込みでない場合）。
        if !force, let cached = cache.objects(server: server, objectID: oid) {
            objects = cached
            isLoading = false
            error = nil
            return
        }
        isLoading = true
        error = nil
        do {
            let items = try await client.browseChildren(controlURL: controlURL, objectID: oid)
            objects = items
            cache.store(items, server: server, objectID: oid)
        } catch is CancellationError {
            // pull-to-refresh などで前の読み込みが中断された正常なキャンセル。エラー表示しない。
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession 層でのキャンセル（-999）も同様に無視する。
        } catch {
            self.error = LibraryModel.message(for: error)
        }
        isLoading = false
    }

    /// 保存パスをルート("0")から辿って現在の objectID を再解決する。
    /// 各階層でフォルダ名が一致するコンテナを辿る。見つからなければ nil。
    private func resolvePath(controlURL: URL) async -> String? {
        var current = "0"
        for name in path {
            guard let objects = try? await client.browseChildren(controlURL: controlURL, objectID: current) else {
                return nil
            }
            let containers = objects.compactMap { obj -> MediaContainer? in
                if case .container(let c) = obj { return c }
                return nil
            }
            guard let match = containers.first(where: { $0.title == name }) else { return nil }
            current = match.id
        }
        return current
    }
}
