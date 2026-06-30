import Foundation

/// デバイス記述（device description）XML を取得・解析し、`MediaServer` を構築する。
public struct DeviceDescriptionLoader: Sendable {
    public typealias Transport = @Sendable (_ url: URL) async throws -> Data

    public enum LoaderError: Error, Equatable {
        /// XML として解析できなかった。`snippet` は受信本文の先頭（診断用）。
        case malformedXML(snippet: String)
        case noContentDirectory
        /// HTTP ステータスが 2xx 以外（例: 404 / 500）。
        case httpStatus(Int)
    }

    let transport: Transport

    public init(transport: @escaping Transport = DeviceDescriptionLoader.urlSessionTransport) {
        self.transport = transport
    }

    public static let urlSessionTransport: Transport = { url in
        let (data, response) = try await DLNAHTTP.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoaderError.httpStatus(http.statusCode)
        }
        return data
    }

    /// 記述 URL から取得して `MediaServer` を返す。
    public func load(descriptionURL: URL, origin: MediaServer.Origin = .manual) async throws -> MediaServer {
        let data = try await transport(descriptionURL)
        return try Self.parse(data, descriptionURL: descriptionURL, origin: origin)
    }

    /// デバイス記述 XML を解析する（純粋関数）。
    public static func parse(
        _ data: Data,
        descriptionURL: URL,
        origin: MediaServer.Origin = .manual
    ) throws -> MediaServer {
        let delegate = DeviceDescriptionDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw LoaderError.malformedXML(snippet: snippet(from: data)) }

        // controlURL は URLBase（あれば）または記述 URL を基準に絶対化する。
        let base = delegate.urlBase.flatMap { URL(string: $0) } ?? descriptionURL
        guard let rawControl = delegate.contentDirectoryControlURL,
              let controlURL = URL(string: rawControl, relativeTo: base)?.absoluteURL else {
            throw LoaderError.noContentDirectory
        }

        let id = delegate.udn?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = delegate.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MediaServer(
            id: (id?.isEmpty == false ? id! : descriptionURL.absoluteString),
            friendlyName: (name?.isEmpty == false ? name! : descriptionURL.host ?? "DLNA Server"),
            descriptionURL: descriptionURL,
            contentDirectoryControlURL: controlURL,
            origin: origin
        )
    }

    /// 受信本文の先頭を診断用の短い文字列にする（改行は詰める）。
    static func snippet(from data: Data, limit: Int = 120) -> String {
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(空の応答)" : text
    }
}

/// デバイス記述 XML から friendlyName / UDN / URLBase / ContentDirectory controlURL を抽出する。
private final class DeviceDescriptionDelegate: NSObject, XMLParserDelegate {
    var friendlyName: String?
    var udn: String?
    var urlBase: String?
    var contentDirectoryControlURL: String?

    // serviceList 内の各 service を組み立てる
    private var inService = false
    private var serviceType = ""
    private var serviceControlURL = ""

    private var current: String?
    private var buffer = ""

    private func local(_ name: String) -> String {
        name.components(separatedBy: ":").last ?? name
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch local(elementName) {
        case "service":
            inService = true
            serviceType = ""
            serviceControlURL = ""
        case "friendlyName", "UDN", "URLBase", "serviceType", "controlURL":
            current = local(elementName)
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch local(elementName) {
        case "friendlyName":
            if friendlyName == nil { friendlyName = value }
        case "UDN":
            if udn == nil { udn = value }
        case "URLBase":
            if urlBase == nil, !value.isEmpty { urlBase = value }
        case "serviceType":
            if inService { serviceType = value }
        case "controlURL":
            if inService { serviceControlURL = value }
        case "service":
            if contentDirectoryControlURL == nil,
               serviceType.contains("ContentDirectory") {
                contentDirectoryControlURL = serviceControlURL
            }
            inService = false
        default:
            break
        }
        current = nil
    }
}
