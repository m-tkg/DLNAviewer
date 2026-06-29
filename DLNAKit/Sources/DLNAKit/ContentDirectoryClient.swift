import Foundation

/// ContentDirectory:Browse の結果。
public struct BrowseResult: Sendable, Equatable {
    public var objects: [DIDLObject]
    public var numberReturned: Int
    public var totalMatches: Int

    public init(objects: [DIDLObject], numberReturned: Int, totalMatches: Int) {
        self.objects = objects
        self.numberReturned = numberReturned
        self.totalMatches = totalMatches
    }
}

/// ContentDirectory サービスへ SOAP `Browse` を発行するクライアント。
public struct ContentDirectoryClient: Sendable {
    public enum BrowseFlag: String, Sendable {
        case directChildren = "BrowseDirectChildren"
        case metadata = "BrowseMetadata"
    }

    public enum ClientError: Error, Equatable {
        case malformedResponse
        case httpError(Int)
    }

    /// ネットワーク送信を抽象化（テスト時に差し替え可能）。
    public typealias Transport = @Sendable (_ request: URLRequest) async throws -> Data

    static let serviceType = "urn:schemas-upnp-org:service:ContentDirectory:1"

    let transport: Transport

    public init(transport: @escaping Transport = ContentDirectoryClient.urlSessionTransport) {
        self.transport = transport
    }

    public static let urlSessionTransport: Transport = { request in
        let (data, response) = try await DLNAHTTP.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.httpError(http.statusCode)
        }
        return data
    }

    public func browse(
        controlURL: URL,
        objectID: String,
        browseFlag: BrowseFlag = .directChildren,
        filter: String = "*",
        startingIndex: Int = 0,
        requestedCount: Int = 0,
        sortCriteria: String = ""
    ) async throws -> BrowseResult {
        let body = Self.makeBrowseBody(
            objectID: objectID,
            browseFlag: browseFlag,
            filter: filter,
            startingIndex: startingIndex,
            requestedCount: requestedCount,
            sortCriteria: sortCriteria
        )
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(Self.serviceType)#Browse\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = Data(body.utf8)

        let data = try await transport(request)
        // res の相対 URL は controlURL を基準に解決する。
        return try Self.parseBrowseResponse(data, baseURL: controlURL)
    }

    /// 全ページを取得して結合する（大きなフォルダを 1 リクエストで全件取得して詰まるのを避ける）。
    public func browseAll(
        controlURL: URL,
        objectID: String,
        filter: String = "*",
        sortCriteria: String = "",
        pageSize: Int = 200
    ) async throws -> [DIDLObject] {
        var all: [DIDLObject] = []
        var start = 0
        while true {
            let result = try await browse(
                controlURL: controlURL, objectID: objectID,
                filter: filter, startingIndex: start, requestedCount: pageSize, sortCriteria: sortCriteria
            )
            all.append(contentsOf: result.objects)
            let returned = result.numberReturned
            start += returned
            // このページが空（これ以上進めない）か、総数に達したら終了。
            // returned==0 を必ず終了条件にすることで、StartingIndex を無視するサーバでの無限ループも防ぐ。
            if returned == 0 || start >= result.totalMatches { break }
        }
        return all
    }

    // MARK: - SOAP 組み立て / 解析（純粋関数）

    /// SOAP `Browse` リクエストのエンベロープ本体を生成する。
    public static func makeBrowseBody(
        objectID: String,
        browseFlag: BrowseFlag,
        filter: String,
        startingIndex: Int,
        requestedCount: Int,
        sortCriteria: String
    ) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:Browse xmlns:u="\(serviceType)">
        <ObjectID>\(xmlEscape(objectID))</ObjectID>
        <BrowseFlag>\(browseFlag.rawValue)</BrowseFlag>
        <Filter>\(xmlEscape(filter))</Filter>
        <StartingIndex>\(startingIndex)</StartingIndex>
        <RequestedCount>\(requestedCount)</RequestedCount>
        <SortCriteria>\(xmlEscape(sortCriteria))</SortCriteria>
        </u:Browse>
        </s:Body>
        </s:Envelope>
        """
    }

    /// SOAP `BrowseResponse` を解析し、`Result`（DIDL-Lite）と件数を取り出す。
    public static func parseBrowseResponse(_ data: Data, baseURL: URL?) throws -> BrowseResult {
        let delegate = BrowseResponseDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let didl = delegate.result else {
            throw ClientError.malformedResponse
        }
        let objects = try DIDLParser.parse(didl, baseURL: baseURL)
        return BrowseResult(
            objects: objects,
            numberReturned: delegate.numberReturned ?? objects.count,
            totalMatches: delegate.totalMatches ?? objects.count
        )
    }
}

/// XML テキストノード／属性値用のエスケープ。
func xmlEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&apos;"
        default: out.append(ch)
        }
    }
    return out
}

/// SOAP BrowseResponse の `Result` / `NumberReturned` / `TotalMatches` を取り出す。
private final class BrowseResponseDelegate: NSObject, XMLParserDelegate {
    var result: String?
    var numberReturned: Int?
    var totalMatches: Int?

    private var current: String?
    private var buffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "Result", "NumberReturned", "TotalMatches":
            current = local
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
        let local = elementName.components(separatedBy: ":").last ?? elementName
        switch local {
        case "Result": result = buffer
        case "NumberReturned": numberReturned = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        case "TotalMatches": totalMatches = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return
        }
        current = nil
    }
}
