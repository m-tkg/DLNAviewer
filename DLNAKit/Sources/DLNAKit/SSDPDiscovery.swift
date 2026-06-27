import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "com.mtkg.dlnaviewer", category: "SSDP")

/// SSDP の M-SEARCH 応答 1 件。
public struct SSDPResponse: Hashable, Sendable {
    /// デバイス記述 XML の URL（`LOCATION` ヘッダ）。
    public var location: URL
    /// 検索対象（`ST` ヘッダ）。
    public var searchTarget: String
    /// 一意なサービス名（`USN` ヘッダ）。
    public var usn: String

    public init(location: URL, searchTarget: String, usn: String) {
        self.location = location
        self.searchTarget = searchTarget
        self.usn = usn
    }
}

/// SSDP（Simple Service Discovery Protocol）でメディアサーバーを探索する。
///
/// - Important: iOS では `239.255.255.250:1900` へのマルチキャスト送受信に
///   `com.apple.developer.networking.multicast` エンタイトルメント（Apple の承認）が必要。
public final class SSDPDiscovery: Sendable {
    /// MediaServer デバイスを探す検索対象。
    public static let mediaServerTarget = "urn:schemas-upnp-org:device:MediaServer:1"
    /// ContentDirectory サービスを探す検索対象。
    public static let contentDirectoryTarget = "urn:schemas-upnp-org:service:ContentDirectory:1"

    /// 既定の検索対象（MediaServer と ContentDirectory の両方を投げて取りこぼしを減らす）。
    public static let defaultTargets = [mediaServerTarget, contentDirectoryTarget]

    static let multicastHost = "239.255.255.250"
    static let multicastPort: UInt16 = 1900

    public init() {}

    /// SSDP の M-SEARCH リクエスト文字列を生成する。
    public static func makeSearchRequest(
        searchTarget: String = mediaServerTarget,
        mx: Int = 2
    ) -> String {
        // 各行は CRLF 区切り、末尾は空行。
        [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(multicastHost):\(multicastPort)",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(searchTarget)",
            "USER-AGENT: DLNAviewer/1.0 UPnP/1.0",
            "",
            "",
        ].joined(separator: "\r\n")
    }

    /// M-SEARCH 応答（HTTP ライクなテキスト）を解析する。LOCATION が無ければ nil。
    public static func parseResponse(_ text: String) -> SSDPResponse? {
        var headers: [String: String] = [:]
        // CRLF は 1 つの grapheme cluster になるため isNewline で分割する。
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] == nil { headers[key] = value }
        }
        guard let location = headers["LOCATION"], let url = URL(string: location) else {
            return nil
        }
        return SSDPResponse(
            location: url,
            searchTarget: headers["ST"] ?? "",
            usn: headers["USN"] ?? ""
        )
    }

    /// 指定時間だけ探索し、発見した応答（USN で重複排除）を返す。
    ///
    /// UDP は取りこぼしが起きやすいため、待ち受け中に各検索対象へ複数回 M-SEARCH を送る。
    /// - Parameters:
    ///   - targets: 検索対象 ST の一覧。
    ///   - duration: 待ち受け秒数。
    public func search(
        targets: [String] = defaultTargets,
        duration: TimeInterval = 4
    ) async -> [SSDPResponse] {
        let box = ContinuationBox()
        return await withCheckedContinuation { continuation in
            box.store(continuation)
            let collector = ResponseCollector()
            let queue = DispatchQueue(label: "dlna.ssdp")

            func finish(_ group: NWConnectionGroup?) {
                group?.cancel()
                box.resumeOnce(with: collector.snapshot())
            }

            let multicast: NWMulticastGroup
            do {
                multicast = try NWMulticastGroup(
                    for: [.hostPort(host: NWEndpoint.Host(Self.multicastHost),
                                    port: NWEndpoint.Port(rawValue: Self.multicastPort)!)]
                )
            } catch {
                log.error("NWMulticastGroup 生成失敗: \(String(describing: error), privacy: .public)")
                box.resumeOnce(with: [])
                return
            }

            let group = NWConnectionGroup(with: multicast, using: .udp)
            group.setReceiveHandler(maximumMessageSize: 65_536, rejectOversizedMessages: true) { _, content, _ in
                if let content, let text = String(data: content, encoding: .utf8),
                   let response = Self.parseResponse(text) {
                    log.debug("受信: \(response.location.absoluteString, privacy: .public)")
                    collector.add(response)
                }
            }

            group.stateUpdateHandler = { state in
                log.debug("group state: \(String(describing: state), privacy: .public)")
                switch state {
                case .ready:
                    // ready 直後と、その後数回に分けて再送する。
                    for (index, delay) in [0.0, 0.7, 1.5].enumerated() {
                        queue.asyncAfter(deadline: .now() + delay) {
                            for target in targets {
                                let request = Self.makeSearchRequest(searchTarget: target)
                                group.send(content: Data(request.utf8)) { _ in }
                            }
                        }
                        _ = index
                    }
                case .failed, .cancelled:
                    box.resumeOnce(with: collector.snapshot())
                default:
                    break
                }
            }

            group.start(queue: queue)

            queue.asyncAfter(deadline: .now() + duration) {
                log.debug("探索終了: \(collector.snapshot().count) 件")
                finish(group)
            }
        }
    }
}

/// `CheckedContinuation` を一度だけ resume するためのスレッドセーフなラッパ。
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[SSDPResponse], Never>?
    private var resumed = false

    func store(_ continuation: CheckedContinuation<[SSDPResponse], Never>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
    }

    func resumeOnce(with value: [SSDPResponse]) {
        lock.lock()
        guard !resumed, let continuation else { lock.unlock(); return }
        resumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
    }
}

/// 受信した応答を USN で重複排除しつつ蓄積する（スレッドセーフ）。
private final class ResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var byUSN: [String: SSDPResponse] = [:]
    private var order: [String] = []

    func add(_ response: SSDPResponse) {
        lock.lock(); defer { lock.unlock() }
        // 同一デバイスは複数 USN で応答するため、記述 URL（LOCATION）単位で重複排除する。
        let key = response.location.absoluteString
        if byUSN[key] == nil { order.append(key) }
        byUSN[key] = response
    }

    func snapshot() -> [SSDPResponse] {
        lock.lock(); defer { lock.unlock() }
        return order.compactMap { byUSN[$0] }
    }
}
