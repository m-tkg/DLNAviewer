import Foundation

/// DIDL-Lite XML（ContentDirectory:Browse の Result）を解析するパーサ。
public enum DIDLParser {
    public enum ParseError: Error, Equatable {
        case invalidXML
    }

    /// DIDL-Lite XML 文字列を解析し、コンテナ／アイテムの並びを返す。
    /// - Parameters:
    ///   - xml: `<DIDL-Lite>…</DIDL-Lite>` 文字列。
    ///   - baseURL: 相対 `res` URL を絶対化するための基準 URL（サーバーの記述 URL 等）。
    public static func parse(_ xml: String, baseURL: URL? = nil) throws -> [DIDLObject] {
        guard let data = xml.data(using: .utf8) else { throw ParseError.invalidXML }
        let delegate = Delegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw ParseError.invalidXML }
        return delegate.objects
    }

    /// `res@duration`（`H:MM:SS[.fff]` 形式）を秒に変換する。
    static func parseDuration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

// MARK: - XMLParser delegate

private final class Delegate: NSObject, XMLParserDelegate {
    let baseURL: URL?
    var objects: [DIDLObject] = []

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    // 構築中の状態
    private enum Kind { case container, item }
    private var kind: Kind?
    private var id = ""
    private var parentID = ""
    private var childCount: Int?
    private var title = ""
    private var upnpClass = ""
    private var resources: [MediaResource] = []
    private var thumbnails: [MediaResource] = []
    private var albumArtURI: URL?

    // res 要素の途中状態
    private var resAttributes: [String: String]?
    private var resText = ""

    // 現在テキストを蓄積している対象
    private var textBuffer = ""
    private var capturing: Capture = .none
    private enum Capture { case none, title, upnpClass, res, albumArt }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        switch elementName {
        case "container", "item":
            kind = elementName == "container" ? .container : .item
            id = attributeDict["id"] ?? ""
            parentID = attributeDict["parentID"] ?? ""
            childCount = attributeDict["childCount"].flatMap { Int($0) }
            title = ""
            upnpClass = ""
            resources = []
            thumbnails = []
            albumArtURI = nil
        case "dc:title", "title":
            capturing = .title
            textBuffer = ""
        case "upnp:class", "class":
            capturing = .upnpClass
            textBuffer = ""
        case "upnp:albumArtURI", "albumArtURI":
            capturing = .albumArt
            textBuffer = ""
        case "res":
            capturing = .res
            resAttributes = attributeDict
            resText = ""
            textBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capturing != .none else { return }
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "dc:title", "title":
            title = textBuffer
            capturing = .none
        case "upnp:class", "class":
            upnpClass = textBuffer
            capturing = .none
        case "upnp:albumArtURI", "albumArtURI":
            let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            albumArtURI = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            capturing = .none
        case "res":
            if let resource = makeResource(text: textBuffer, attributes: resAttributes ?? [:]) {
                // 画像 res はサムネイル、それ以外は再生リソースに分類する。
                if (resource.mimeType ?? "").hasPrefix("image/") {
                    thumbnails.append(resource)
                } else {
                    resources.append(resource)
                }
            }
            resAttributes = nil
            capturing = .none
        case "container", "item":
            finishObject()
        default:
            break
        }
    }

    private func makeResource(text: String, attributes: [String: String]) -> MediaResource? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else { return nil }
        return MediaResource(
            url: url,
            protocolInfo: attributes["protocolInfo"],
            durationSeconds: attributes["duration"].flatMap(DIDLParser.parseDuration),
            size: attributes["size"].flatMap { Int64($0) },
            resolution: attributes["resolution"]
        )
    }

    private func finishObject() {
        switch kind {
        case .container:
            objects.append(.container(MediaContainer(
                id: id, parentID: parentID, title: title, childCount: childCount
            )))
        case .item:
            objects.append(.item(MediaItem(
                id: id, parentID: parentID, title: title, upnpClass: upnpClass,
                resources: resources, thumbnails: thumbnails, albumArtURI: albumArtURI
            )))
        case .none:
            break
        }
        kind = nil
    }
}
