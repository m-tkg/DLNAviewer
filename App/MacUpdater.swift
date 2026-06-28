#if os(macOS)
import AppKit
import Foundation
import Observation
import DLNAKit

/// 公開 GitHub API へアクセスし、最新リリースの取得と zip ダウンロードを行う（public リポジトリのため認証不要）。
struct UpdateService {
    static let repoFullName = "m-tkg/DLNAviewer"
    static let apiBase = "https://api.github.com"
    private static let userAgent = "DLNAviewer"

    /// 常に最新を取りたいのでキャッシュを使わない専用セッション
    /// （GitHub API は cache-control を返すため、共有セッションだと古い結果になる）。
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    enum ServiceError: LocalizedError {
        case requestFailed(Int)
        case decodeFailed
        case noZipAsset
        case downloadFailed(Int)

        var errorDescription: String? {
            switch self {
            case .requestFailed(let code): return "リリース情報の取得に失敗しました（HTTP \(code)）。"
            case .decodeFailed: return "リリース情報を解析できませんでした。"
            case .noZipAsset: return "リリースに zip アセットがありません。"
            case .downloadFailed(let code): return "ダウンロードに失敗しました（HTTP \(code)）。"
            }
        }
    }

    /// 現在のアプリバージョン（CFBundleShortVersionString）。
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 最新リリース情報を取得する。
    func fetchLatestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "\(Self.apiBase)/repos/\(Self.repoFullName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.requestFailed(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.requestFailed(http.statusCode) }
        guard let release = try? JSONDecoder().decode(ReleaseInfo.self, from: data) else {
            throw ServiceError.decodeFailed
        }
        return release
    }

    /// リリースの zip アセットを `directory` にダウンロードし、保存先 URL を返す。
    func downloadReleaseZip(_ release: ReleaseInfo, into directory: URL) async throws -> URL {
        guard let assetURL = release.zipAssetURL else { throw ServiceError.noZipAsset }
        var request = URLRequest(url: assetURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.downloadFailed(http.statusCode)
        }
        let destination = directory.appendingPathComponent("DLNAviewer.zip")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}

/// 最新リリースの zip をダウンロード・展開し、起動中の `.app` を上書きして再起動する。
///
/// 実行中のバンドルは自プロセスでは上書きできないため、旧プロセスの終了を待ってから
/// 入れ替える切り離しシェルスクリプトを起動し、自身は `NSApp.terminate` で終了する。
@MainActor
enum SelfUpdater {
    enum UpdateError: LocalizedError {
        case notWritable(String)
        case bundleNotFound
        case bundleIDMismatch
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notWritable(let path): return "アプリを書き換えられません（\(path)）。/Applications などに移動してから再試行してください。"
            case .bundleNotFound: return "ダウンロードしたアーカイブにアプリが見つかりません。"
            case .bundleIDMismatch: return "ダウンロードしたアプリの識別子が一致しません。"
            case .commandFailed(let msg): return "更新処理に失敗しました: \(msg)"
            }
        }
    }

    /// 更新を実行する。成功時はアプリを終了するため呼び出し元には戻らない。
    static func performUpdate(_ release: ReleaseInfo, service: UpdateService) async throws {
        let bundleURL = Bundle.main.bundleURL
        try ensureWritable(bundleURL)

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("dlnaviewer-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        // 1. zip ダウンロード
        let zipURL = try await service.downloadReleaseZip(release, into: workDir)

        // 2. 展開（.app の展開には ditto が最適）
        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await runAndWait("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])

        // 3. .app を特定して識別子を検証
        guard let newApp = try firstApp(in: extractDir) else { throw UpdateError.bundleNotFound }
        guard let newID = Bundle(url: newApp)?.bundleIdentifier,
              newID == Bundle.main.bundleIdentifier else {
            throw UpdateError.bundleIDMismatch
        }

        // 4. 入れ替えスクリプトを切り離し起動し、自身を終了
        try launchReplaceScript(newApp: newApp, dest: bundleURL)
        NSApp.terminate(nil)
    }

    private static func ensureWritable(_ bundleURL: URL) throws {
        let fm = FileManager.default
        let parent = bundleURL.deletingLastPathComponent().path
        guard fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: bundleURL.path) else {
            throw UpdateError.notWritable(bundleURL.path)
        }
    }

    private static func firstApp(in directory: URL) throws -> URL? {
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return entries.first { $0.pathExtension == "app" }
    }

    /// 旧プロセス終了を待って `.app` を入れ替え、再起動する切り離しスクリプト。
    /// パスは環境変数で渡し、空白を含むパスでも安全にする。
    private static func launchReplaceScript(newApp: URL, dest: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.bak"
        mv "$DEST" "$DEST.bak" || exit 1
        if ! mv "$NEW" "$DEST"; then
          mv "$DEST.bak" "$DEST"
          exit 1
        fi
        rm -rf "$DEST.bak"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = ["DEST": dest.path, "NEW": newApp.path, "PATH": "/usr/bin:/bin"]
        try process.run()
    }

    private static func runAndWait(_ executable: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stderr = Pipe()
            process.standardError = stderr
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let msg = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: UpdateError.commandFailed(msg.isEmpty ? "exit \(proc.terminationStatus)" : msg))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

/// 設定画面のアップデート UI を駆動する状態モデル。
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading
        case failed(String)
    }

    private(set) var state: State = .idle
    let currentVersion = UpdateService.currentVersion
    private let service = UpdateService()

    /// 最新リリースを確認し、現在より新しければ `.available` にする。
    func check() async {
        state = .checking
        do {
            let release = try await service.fetchLatestRelease()
            if VersionComparator.isNewer(tag: release.tagName, than: currentVersion) {
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// ダウンロード→入れ替え→再起動。成功時はアプリが終了する。
    func update(to release: ReleaseInfo) async {
        state = .downloading
        do {
            try await SelfUpdater.performUpdate(release, service: service)
            // 成功すると NSApp.terminate されるためここには戻らない。
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
#endif
