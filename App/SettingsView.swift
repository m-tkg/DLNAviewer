import SwiftUI
import DLNAKit

/// アプリ設定。
struct SettingsView: View {
    @AppStorage("seekUnitTop") private var seekUnitTop = 60
    @AppStorage("seekUnitBottom") private var seekUnitBottom = 30
    @AppStorage("thumbnailSize") private var thumbnailSize = 1   // 0=小, 1=中, 2=大
    @AppStorage("skipSeconds") private var skipSeconds = 10
    @AppStorage("doubleTapSeconds") private var doubleTapSeconds = 30
    @Environment(\.dismiss) private var dismiss

    /// 戻る/進むボタンの秒数（SF Symbol が用意されている値）。
    private let skipOptions = [10, 15, 30, 45, 60]

    @State private var downloadBytes: Int64 = 0
    @State private var cacheBytes: Int64 = 0
    @State private var confirmDeleteDownloads = false
    @State private var orphanScanner = OrphanScanner()
    @State private var orphanScanning = false
    @State private var orphanOutcome: OrphanScanner.Outcome?
    @State private var confirmDeleteOrphans = false
    #if os(macOS)
    // 起動時チェック（ServerListView）と状態を共有する。
    @State private var updater = UpdateChecker.shared
    #endif

    private let options = [5, 10, 15, 30, 45, 60, 90, 120, 180, 300]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("上半分のスワイプ", selection: $seekUnitTop) {
                        ForEach(options, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                    Picker("下半分のスワイプ", selection: $seekUnitBottom) {
                        ForEach(options, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                } header: {
                    Text("スワイプシークの単位")
                } footer: {
                    Text("再生画面でコントロール非表示のとき、画面の上半分／下半分を左右スワイプした 1 単位あたりの秒数です。")
                }

                Section {
                    Picker("戻る/進むボタン", selection: $skipSeconds) {
                        ForEach(skipOptions, id: \.self) { Text("\($0)秒").tag($0) }
                    }
                    Picker("ダブルタップ", selection: $doubleTapSeconds) {
                        ForEach(skipOptions, id: \.self) { Text("\($0)秒").tag($0) }
                    }
                } header: {
                    Text("スキップ秒数")
                } footer: {
                    Text("再生画面の戻る/進むボタンと、中央より左右のダブルタップでの移動秒数です。")
                }

                Section("表示") {
                    Picker("サムネイルのサイズ", selection: $thumbnailSize) {
                        Text("小").tag(0)
                        Text("中").tag(1)
                        Text("大").tag(2)
                    }
                    #if os(iOS)
                    .pickerStyle(.segmented)
                    #endif
                }

                Section {
                    LabeledContent("ダウンロード", value: formatBytes(downloadBytes))
                    Button("ダウンロードをすべて削除", role: .destructive) {
                        confirmDeleteDownloads = true
                    }
                    .disabled(downloadBytes == 0)

                    LabeledContent("キャッシュ", value: formatBytes(cacheBytes))
                    Button("キャッシュをクリア") {
                        clearCaches()
                        refreshStorage()
                    }

                } header: {
                    Text("ストレージ")
                } footer: {
                    Text("キャッシュはサムネイルや HTTP の一時データです。")
                }

                orphanScanSection

                #if os(macOS)
                updateSection
                #endif
            }
            .navigationTitle("設定")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .task { refreshStorage() }
            .confirmationDialog("すべてのダウンロードを削除しますか？",
                                isPresented: $confirmDeleteDownloads, titleVisibility: .visible) {
                Button("すべて削除", role: .destructive) {
                    DownloadManager.shared.deleteAll()
                    refreshStorage()
                }
                Button("キャンセル", role: .cancel) {}
            }
            .confirmationDialog("孤立データを削除しますか？",
                                isPresented: $confirmDeleteOrphans, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let outcome = orphanOutcome, outcome.allReachable {
                        orphanScanner.removeOrphans(outcome.report)
                        orphanOutcome = nil
                        refreshStorage()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                if let r = orphanOutcome?.report {
                    Text("評価 \(r.ratings.count)・ブックマーク \(r.bookmarks.count)・タグ \(r.tags.count)・サムネ \(r.thumbnails.count)・ダウンロード \(r.downloads.count) を削除します。")
                }
            }
        }
        #if os(macOS)
        // sheet はコンテンツ駆動で幅が詰まり、LabeledContent のラベル（例「現在のバージョン」）
        // が見切れる。十分な最小サイズを与える。
        .frame(minWidth: 460, idealWidth: 480, minHeight: 560)
        #endif
    }

    /// 孤立検出のスキャン対象（手動＋発見済みサーバ。どの画面から設定を開いても取得できる）。
    private var scanServers: [MediaServer] {
        LibraryModel.shared.servers.compactMap(\.server) + LibraryModel.shared.discovered
    }

    /// サーバ再スキャンによる孤立データ検出セクション。
    @ViewBuilder
    private var orphanScanSection: some View {
        Section {
            if orphanScanning {
                HStack { ProgressView().controlSize(.small); Text("サーバを再スキャン中…") }
            } else if let outcome = orphanOutcome {
                if !outcome.allReachable {
                    Label("一部のサーバに到達できないため削除できません", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                LabeledContent("サーバに無いデータ", value: "\(outcome.report.total) 件")
                // 種類別の内訳（0 件の種類は省略）。
                let r = outcome.report
                if r.ratings.count > 0 { LabeledContent("　評価", value: "\(r.ratings.count) 件").foregroundStyle(.secondary) }
                if r.bookmarks.count > 0 { LabeledContent("　ブックマーク", value: "\(r.bookmarks.count) 件").foregroundStyle(.secondary) }
                if r.tags.count > 0 { LabeledContent("　タグ", value: "\(r.tags.count) 件").foregroundStyle(.secondary) }
                if r.thumbnails.count > 0 { LabeledContent("　サムネ上書き", value: "\(r.thumbnails.count) 件").foregroundStyle(.secondary) }
                if r.downloads.count > 0 { LabeledContent("　ダウンロード", value: "\(r.downloads.count) 件").foregroundStyle(.secondary) }
                if outcome.report.total > 0 && outcome.allReachable {
                    Button("孤立データを削除", role: .destructive) { confirmDeleteOrphans = true }
                }
            }
            Button("サーバを再スキャンして検出") { Task { await scanOrphans() } }
                .disabled(orphanScanning || scanServers.isEmpty)
        } header: {
            Text("孤立データ（サーバ照合）")
        } footer: {
            Text(scanServers.isEmpty
                 ? "サーバ一覧の画面から設定を開くと実行できます。登録サーバを再スキャンし、どのサーバにも存在しない動画のデータを検出します。"
                 : "登録サーバを再スキャンし、どのサーバにも存在しない動画の評価・ブックマーク・タグ・サムネ上書き・ダウンロードを孤立として検出します。全サーバに到達できた場合のみ削除できます。")
        }
    }

    private func scanOrphans() async {
        orphanScanning = true
        defer { orphanScanning = false }
        orphanOutcome = await orphanScanner.scan(servers: scanServers)
    }

    private func refreshStorage() {
        downloadBytes = DownloadManager.shared.totalDownloadedBytes()
        cacheBytes = Int64(URLCache.shared.currentDiskUsage)
    }

    private func clearCaches() {
        URLCache.shared.removeAllCachedResponses()
        ThumbnailCache.shared.clearAll()
        BrowseCache.shared.clearAll()
    }

    static func label(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)秒" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m)分" : "\(m)分\(s)秒"
    }

    #if os(macOS)
    /// アップデート確認・自動更新（macOS のみ。GitHub Release から取得）。
    @ViewBuilder
    private var updateSection: some View {
        Section {
            LabeledContent("現在のバージョン", value: updater.currentVersion)

            switch updater.state {
            case .idle, .failed:
                Button("アップデートを確認") { Task { await updater.check() } }
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("確認中…") }
            case .upToDate:
                Label("最新です", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Button("再確認") { Task { await updater.check() } }
            case .available(let release):
                Label("新しいバージョン \(release.tagName) があります", systemImage: "arrow.down.circle")
                Button("ダウンロードしてインストール") { Task { await updater.update(to: release) } }
            case .downloading:
                HStack { ProgressView().controlSize(.small); Text("ダウンロードして更新中…") }
            }

            if case .failed(let message) = updater.state {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("アップデート")
        } footer: {
            Text("GitHub のリリースから最新版を確認し、その場で更新します。更新後は自動で再起動します。")
        }
    }
    #endif
}
