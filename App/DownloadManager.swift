import Foundation
import Observation
import DLNAKit

/// 動画のダウンロード状態。
enum DownloadState: Equatable {
    case none
    case downloading(Double)   // 進捗 0...1
    case downloaded

    var isDownloaded: Bool { self == .downloaded }
    var isActive: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// ダウンロード済みファイルのメタ情報（永続化）。
private struct DownloadRecord: Codable {
    var filename: String
    var size: Int64
    var item: MediaItem
}

/// 動画ファイルを端末ローカルへダウンロード・管理する。
@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()

    /// アイテム ID → 状態。
    private var states: [String: DownloadState] = [:]
    /// アイテム ID → 記録（一覧表示のため観測対象）。
    private var records: [String: DownloadRecord] = [:]

    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var observations: [String: NSKeyValueObservation] = [:]

    private init() {
        records = Self.loadIndex()
        // 実ファイルがあるものを「済」として状態に反映。
        for (id, record) in records {
            if FileManager.default.fileExists(atPath: Self.downloadsDir().appendingPathComponent(record.filename).path) {
                states[id] = .downloaded
            }
        }
    }

    // MARK: 状態・情報

    func state(for item: MediaItem) -> DownloadState {
        states[item.id] ?? .none
    }

    /// ダウンロード済みファイルのサイズ。未ダウンロードなら DIDL の res@size を返す。
    func size(for item: MediaItem) -> Int64? {
        if let record = records[item.id] { return record.size }
        return item.preferredVideoResource?.size
    }

    /// ダウンロード済みならローカル URL を返す。
    func localURL(for item: MediaItem) -> URL? {
        guard let record = records[item.id] else { return nil }
        let url = Self.downloadsDir().appendingPathComponent(record.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 再生に使う URL（ダウンロード済みはローカル、なければリモート）。
    func preferredURL(for item: MediaItem) -> URL? {
        localURL(for: item) ?? item.preferredVideoResource?.url
    }

    /// ダウンロード済みの動画一覧（実ファイルがあるもの・タイトル順）。
    func downloadedItems() -> [MediaItem] {
        records.values
            .filter { FileManager.default.fileExists(atPath: Self.downloadsDir().appendingPathComponent($0.filename).path) }
            .map(\.item)
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    // MARK: 操作

    func download(_ item: MediaItem) {
        let id = item.id
        guard let url = item.preferredVideoResource?.url else { return }
        guard !(states[id]?.isActive ?? false), !(states[id]?.isDownloaded ?? false) else { return }

        states[id] = .downloading(0)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension

        let task = URLSession.shared.downloadTask(with: url) { [weak self] temp, _, error in
            // 完了ハンドラ内（バックグラウンド）で temp はまだ有効。同期で移動する。
            var saved: (filename: String, size: Int64)?
            if let temp, error == nil {
                let dir = Self.downloadsDir()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent("\(Self.sanitize(id)).\(ext)")
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.moveItem(at: temp, to: dest)) != nil {
                    let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                    saved = (dest.lastPathComponent, size ?? 0)
                }
            }
            Task { @MainActor in
                guard let self else { return }
                self.observations[id] = nil
                self.tasks[id] = nil
                if let saved {
                    self.records[id] = DownloadRecord(filename: saved.filename, size: saved.size, item: item)
                    Self.saveIndex(self.records)
                    self.states[id] = .downloaded
                } else {
                    self.states[id] = .none
                }
            }
        }

        observations[id] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                if case .downloading = self?.states[id] { self?.states[id] = .downloading(fraction) }
            }
        }
        tasks[id] = task
        task.resume()
    }

    func cancel(_ item: MediaItem) {
        let id = item.id
        tasks[id]?.cancel()
        tasks[id] = nil
        observations[id] = nil
        states[id] = .none
    }

    func delete(_ item: MediaItem) {
        let id = item.id
        if let record = records[id] {
            try? FileManager.default.removeItem(at: Self.downloadsDir().appendingPathComponent(record.filename))
        }
        records[id] = nil
        Self.saveIndex(records)
        states[id] = .none
    }

    // MARK: ストレージ管理

    /// ダウンロード済みファイルの合計バイト数（実ファイル基準）。
    func totalDownloadedBytes() -> Int64 {
        let dir = Self.downloadsDir()
        return records.values.reduce(0) { sum, record in
            let path = dir.appendingPathComponent(record.filename).path
            let size = ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int64) ?? record.size
            return sum + size
        }
    }

    /// すべてのダウンロードを削除する（進行中はキャンセル）。
    func deleteAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        observations.removeAll()
        let dir = Self.downloadsDir()
        for record in records.values {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(record.filename))
        }
        records.removeAll()
        states.removeAll()
        Self.saveIndex(records)
    }

    /// 孤立データ件数: 記録に無いファイル ＋ ファイルが存在しない記録。
    func orphanCount() -> Int {
        let dir = Self.downloadsDir()
        let known = Set(records.values.map(\.filename))
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let orphanFiles = onDisk.filter { !known.contains($0) }.count
        let orphanRecords = records.values.filter {
            !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.filename).path)
        }.count
        return orphanFiles + orphanRecords
    }

    /// 孤立データを削除する。
    /// - Returns: 削除した件数。
    @discardableResult
    func removeOrphans() -> Int {
        let dir = Self.downloadsDir()
        let known = Set(records.values.map(\.filename))
        var removed = 0
        // 記録に無いファイルを削除。
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in onDisk where !known.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            removed += 1
        }
        // ファイルが存在しない記録を削除。
        for (id, record) in records
        where !FileManager.default.fileExists(atPath: dir.appendingPathComponent(record.filename).path) {
            records[id] = nil
            states[id] = nil
            removed += 1
        }
        if removed > 0 { Self.saveIndex(records) }
        return removed
    }

    // MARK: 内部（nonisolated でバックグラウンドからも使用可）

    nonisolated static func downloadsDir() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Downloads", isDirectory: true)
    }

    nonisolated static func sanitize(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private static func indexURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("downloads_index.json")
    }

    fileprivate static func loadIndex() -> [String: DownloadRecord] {
        guard let data = try? Data(contentsOf: indexURL()),
              let dict = try? JSONDecoder().decode([String: DownloadRecord].self, from: data) else {
            return [:]
        }
        return dict
    }

    fileprivate static func saveIndex(_ records: [String: DownloadRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: indexURL())
        }
    }
}

/// バイト数を読みやすい文字列にする。
func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
