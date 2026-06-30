import Foundation
import Observation
import DLNAKit

/// サーバー一覧の状態を管理する ViewModel。
@MainActor
@Observable
final class LibraryModel {
    static let shared = LibraryModel()

    /// 1 サーバーの表示状態（記述 URL の解決結果）。
    struct ServerState: Identifiable {
        var entry: ManualServerEntry
        var server: MediaServer?
        var error: String?
        var isLoading: Bool = false

        var id: UUID { entry.id }
        var displayName: String {
            server?.friendlyName
                ?? entry.name
                ?? entry.descriptionURL.host
                ?? entry.descriptionURL.absoluteString
        }
    }

    private(set) var servers: [ServerState] = []
    /// SSDP で自動探索したサーバー（解決済み）。
    private(set) var discovered: [MediaServer] = []
    var isDiscovering = false
    var addError: String?

    private let store: ManualServerStore
    private let loader: DeviceDescriptionLoader
    private let discovery: SSDPDiscovery

    init(store: ManualServerStore = ManualServerStore(),
         loader: DeviceDescriptionLoader = DeviceDescriptionLoader(),
         discovery: SSDPDiscovery = SSDPDiscovery()) {
        self.store = store
        self.loader = loader
        self.discovery = discovery
    }

    /// 永続化済みの一覧を読み込み、各サーバーを解決する。
    func reload() {
        servers = store.entries().map { ServerState(entry: $0) }
        Task { await resolveAll() }
    }

    /// 全サーバーの記述 URL を解決する。
    func resolveAll() async {
        // 各サーバーを並行に解決し、待ち時間を「最も遅い 1 台」に抑える
        // （到達不能なサーバーがあっても他の解決を待たせない）。self を渡さず loader だけを
        // 並行タスクに渡し、結果は MainActor でまとめて反映する。
        let loader = self.loader
        let entries = servers.indices.map { ($0, servers[$0].entry.descriptionURL) }
        for (index, _) in entries {
            servers[index].isLoading = true
            servers[index].error = nil
        }
        let results = await withTaskGroup(of: (Int, MediaServer?, String?).self) { group -> [(Int, MediaServer?, String?)] in
            for (index, url) in entries {
                group.addTask {
                    do { return (index, try await loader.load(descriptionURL: url, origin: .manual), nil) }
                    catch { return (index, nil, LibraryModel.message(for: error)) }
                }
            }
            var out: [(Int, MediaServer?, String?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (index, server, error) in results where servers.indices.contains(index) {
            servers[index].server = server
            servers[index].error = error
            servers[index].isLoading = false
        }
    }

    /// 指定インデックスのサーバーを解決する。
    func resolve(at index: Int) async {
        guard servers.indices.contains(index) else { return }
        servers[index].isLoading = true
        servers[index].error = nil
        let url = servers[index].entry.descriptionURL
        do {
            let server = try await loader.load(descriptionURL: url, origin: .manual)
            guard servers.indices.contains(index) else { return }
            servers[index].server = server
        } catch {
            guard servers.indices.contains(index) else { return }
            servers[index].error = Self.message(for: error)
        }
        if servers.indices.contains(index) {
            servers[index].isLoading = false
        }
    }

    /// SSDP で同一 LAN のメディアサーバーを探索し、解決して `discovered` を更新する。
    func discover() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        let responses = await discovery.search()
        let manualURLs = Set(servers.map(\.entry.descriptionURL))
        // 各記述 URL を並行に解決する（直列だと到達不能なサーバーで詰まる）。
        let loader = self.loader
        let targets = responses.map(\.location).filter { !manualURLs.contains($0) }
        let resolved = await withTaskGroup(of: MediaServer?.self) { group -> [MediaServer] in
            for url in targets {
                group.addTask { try? await loader.load(descriptionURL: url, origin: .discovered) }
            }
            var found: [MediaServer] = []
            var seenIDs = Set<String>()
            for await server in group {
                guard let server, seenIDs.insert(server.id).inserted else { continue }
                found.append(server)
            }
            return found
        }
        discovered = resolved
    }

    /// 手動でサーバー（記述 URL）を追加する。
    func addManualServer(urlString: String) async {
        addError = nil
        guard let url = Self.normalizeURL(urlString) else {
            addError = "URL の形式が正しくありません"
            return
        }
        let entry = store.add(descriptionURL: url)
        if !servers.contains(where: { $0.id == entry.id }) {
            servers.append(ServerState(entry: entry))
        }
        if let index = servers.firstIndex(where: { $0.id == entry.id }) {
            await resolve(at: index)
        }
    }

    /// 登録済みサーバーの記述 URL と表示名を更新し、再解決する。
    func updateManualServer(id: UUID, urlString: String, name: String?) async {
        addError = nil
        guard let url = Self.normalizeURL(urlString) else {
            addError = "URL の形式が正しくありません"
            return
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = (trimmedName?.isEmpty == false) ? trimmedName : nil
        guard let updated = store.update(id: id, descriptionURL: url, name: cleanName) else { return }
        if let index = servers.firstIndex(where: { $0.id == id }) {
            servers[index].entry = updated
            servers[index].server = nil
            servers[index].error = nil
            await resolve(at: index)
        }
    }

    /// サーバーを一覧と永続化から削除する。
    func remove(_ state: ServerState) {
        store.remove(id: state.entry.id)
        servers.removeAll { $0.id == state.id }
    }

    // MARK: - ヘルパー

    /// 入力文字列を記述 URL に正規化する。スキーム省略時は http を補う。
    static func normalizeURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    nonisolated static func message(for error: Error) -> String {
        if let loaderError = error as? DeviceDescriptionLoader.LoaderError {
            switch loaderError {
            case .malformedXML: return "デバイス記述を解析できませんでした"
            case .noContentDirectory: return "ContentDirectory が見つかりません"
            }
        }
        return (error as NSError).localizedDescription
    }
}
