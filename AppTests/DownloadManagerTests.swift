import Foundation
import Testing
import DLNAKit
@testable import DLNAviewer

/// テスト用の MediaItem。
private func makeItem(id: String = "obj-1", title: String = "Movie.mp4") -> MediaItem {
    let res = MediaResource(url: URL(string: "http://x/\(id)")!,
                            durationSeconds: 3600, size: 100)
    return MediaItem(id: id, parentID: "0", title: title,
                     upnpClass: "object.item.videoItem", resources: [res])
}

@MainActor
@Suite("DownloadManager")
struct DownloadManagerTests {
    /// テストごとに独立した一時ディレクトリへ向けた DownloadManager を作る（実 Documents は触らない）。
    private func makeManager() -> (manager: DownloadManager, downloadsDir: URL, indexURL: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadsDir = base.appendingPathComponent("Downloads", isDirectory: true)
        let indexURL = base.appendingPathComponent("downloads_index.json")
        let manager = DownloadManager(downloadsDirectory: downloadsDir, indexURL: indexURL)
        return (manager, downloadsDir, indexURL)
    }

    private func writeDummyFile(named filename: String, in downloadsDir: URL) -> URL {
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let url = downloadsDir.appendingPathComponent(filename)
        try? Data("dummy".utf8).write(to: url)
        return url
    }

    @Test("記録が無ければ state は none")
    func noRecordMeansNone() {
        let (manager, _, _) = makeManager()
        #expect(manager.state(for: makeItem()) == .none)
    }

    @Test("ダウンロード完了で state が downloaded になり、ローカル URL が引ける")
    func finishDownloadMarksDownloaded() {
        let (manager, downloadsDir, _) = makeManager()
        let item = makeItem()
        let fileURL = writeDummyFile(named: "test.mp4", in: downloadsDir)

        manager.finishDownload(id: item.id, item: item, saved: (filename: "test.mp4", size: 5))

        #expect(manager.state(for: item) == .downloaded)
        #expect(manager.localURL(for: item) == fileURL)
    }

    @Test("保存失敗（saved が nil）なら state は none に戻る")
    func finishDownloadWithoutSavedResetsState() {
        let (manager, _, _) = makeManager()
        let item = makeItem()

        manager.finishDownload(id: item.id, item: item, saved: nil)

        #expect(manager.state(for: item) == .none)
    }

    @Test("削除するとファイルと記録が消える")
    func deleteRemovesFileAndRecord() {
        let (manager, downloadsDir, _) = makeManager()
        let item = makeItem()
        let fileURL = writeDummyFile(named: "test.mp4", in: downloadsDir)
        manager.finishDownload(id: item.id, item: item, saved: (filename: "test.mp4", size: 5))
        #expect(manager.state(for: item) == .downloaded)

        manager.delete(item)

        #expect(manager.state(for: item) == .none)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("再起動相当: 新しいインスタンスが index とファイルから一覧を復元する")
    func restoresDownloadedItemsAcrossRelaunch() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadsDir = base.appendingPathComponent("Downloads", isDirectory: true)
        let indexURL = base.appendingPathComponent("downloads_index.json")
        let manager1 = DownloadManager(downloadsDirectory: downloadsDir, indexURL: indexURL)
        let item = makeItem()
        _ = writeDummyFile(named: "test.mp4", in: downloadsDir)
        manager1.finishDownload(id: item.id, item: item, saved: (filename: "test.mp4", size: 5))

        let manager2 = DownloadManager(downloadsDirectory: downloadsDir, indexURL: indexURL)

        #expect(manager2.downloadedItems().map(\.id) == [item.id])
        #expect(manager2.state(for: item) == .downloaded)
    }

    @Test("ファイルが実在しない記録は一覧に出ない（orphan record）")
    func recordWithoutFileIsExcludedFromList() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloadsDir = base.appendingPathComponent("Downloads", isDirectory: true)
        let indexURL = base.appendingPathComponent("downloads_index.json")
        let manager1 = DownloadManager(downloadsDirectory: downloadsDir, indexURL: indexURL)
        let item = makeItem()
        let fileURL = writeDummyFile(named: "test.mp4", in: downloadsDir)
        manager1.finishDownload(id: item.id, item: item, saved: (filename: "test.mp4", size: 5))
        try? FileManager.default.removeItem(at: fileURL)   // 記録は残したままファイルだけ消す

        let manager2 = DownloadManager(downloadsDirectory: downloadsDir, indexURL: indexURL)

        #expect(manager2.downloadedItems().isEmpty)
        #expect(manager2.orphanCount() == 1)
    }
}
