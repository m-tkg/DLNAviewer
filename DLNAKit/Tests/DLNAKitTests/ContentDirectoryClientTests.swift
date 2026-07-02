import Foundation
import Testing
@testable import DLNAKit

/// テスト用の呼び出し回数カウンタ（transport は逐次 await されるため lock 不要）。
final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}

@Suite("ContentDirectoryClient")
struct ContentDirectoryClientTests {
    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// SOAP ボディから `<StartingIndex>N</StartingIndex>` の N を取り出す。
    static func extractStartingIndex(from body: String) -> Int {
        guard let openRange = body.range(of: "<StartingIndex>"),
              let closeRange = body.range(of: "</StartingIndex>", range: openRange.upperBound..<body.endIndex) else {
            return 0
        }
        return Int(body[openRange.upperBound..<closeRange.lowerBound]) ?? 0
    }

    @Test("Browse の SOAP ボディに必要な要素が含まれる")
    func buildsBrowseBody() {
        let body = ContentDirectoryClient.makeBrowseBody(
            objectID: "64",
            browseFlag: .directChildren,
            filter: "*",
            startingIndex: 0,
            requestedCount: 50,
            sortCriteria: ""
        )
        #expect(body.contains("<u:Browse xmlns:u=\"urn:schemas-upnp-org:service:ContentDirectory:1\">"))
        #expect(body.contains("<ObjectID>64</ObjectID>"))
        #expect(body.contains("<BrowseFlag>BrowseDirectChildren</BrowseFlag>"))
        #expect(body.contains("<Filter>*</Filter>"))
        #expect(body.contains("<StartingIndex>0</StartingIndex>"))
        #expect(body.contains("<RequestedCount>50</RequestedCount>"))
        #expect(body.contains("<SortCriteria></SortCriteria>"))
    }

    @Test("ObjectID 内の特殊文字は XML エスケープされる")
    func escapesObjectID() {
        let body = ContentDirectoryClient.makeBrowseBody(
            objectID: "a&b<c",
            browseFlag: .directChildren,
            filter: "*",
            startingIndex: 0,
            requestedCount: 0,
            sortCriteria: ""
        )
        #expect(body.contains("<ObjectID>a&amp;b&lt;c</ObjectID>"))
    }

    @Test("SOAP レスポンスから Result と件数を解析する")
    func parsesBrowseResponse() throws {
        let data = try Self.fixture("browse_response")
        let result = try ContentDirectoryClient.parseBrowseResponse(data, baseURL: nil)

        #expect(result.numberReturned == 2)
        #expect(result.totalMatches == 2)
        #expect(result.objects.count == 2)
        #expect(result.objects.map(\.title) == ["Movies", "Big Buck Bunny"])
    }

    /// テスト用に BrowseResponse XML を組み立てる。
    static func responseXML(items: [(id: String, title: String)], total: Int) -> Data {
        let didl = items.map {
            "&lt;item id=\"\($0.id)\"&gt;&lt;dc:title&gt;\($0.title)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;&lt;/item&gt;"
        }.joined()
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
        <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
        <Result>&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"&gt;\(didl)&lt;/DIDL-Lite&gt;</Result>
        <NumberReturned>\(items.count)</NumberReturned>
        <TotalMatches>\(total)</TotalMatches>
        </u:BrowseResponse></s:Body></s:Envelope>
        """
        return Data(xml.utf8)
    }

    @Test("browseAll は totalMatches に達するまで全ページを取得して結合する")
    func browseAllPaging() async throws {
        let client = ContentDirectoryClient { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            // 1 ページ目（StartingIndex 0）は 2 件、以降は残り 1 件。総数は 3。
            if body.contains("<StartingIndex>0</StartingIndex>") {
                return Self.responseXML(items: [("1", "A"), ("2", "B")], total: 3)
            }
            return Self.responseXML(items: [("3", "C")], total: 3)
        }
        let objects = try await client.browseAll(
            controlURL: URL(string: "http://x/ctl")!, objectID: "0", pageSize: 2
        )
        #expect(objects.count == 3)
        #expect(objects.map(\.title) == ["A", "B", "C"])
    }

    @Test("browseAll は StartingIndex を無視して同一ページを返し続けるサーバーに対して早期にエラーで打ち切る")
    func browseAllAbortsOnRepeatedPage() async throws {
        let counter = CallCounter()
        let client = ContentDirectoryClient { _ in
            counter.increment()
            // StartingIndex を無視し、常に同じ先頭ページ（同じ id）を返す壊れたサーバーを模す。
            return Self.responseXML(items: [("1", "A"), ("2", "B")], total: 100_000)
        }
        await #expect(throws: ContentDirectoryClient.ClientError.pagingAborted) {
            _ = try await client.browseAll(
                controlURL: URL(string: "http://x/ctl")!, objectID: "0", pageSize: 2
            )
        }
        // 総数（100,000 件）に達するまで待たず、少数回のリクエストで打ち切られること。
        #expect(counter.count <= 3)
    }

    @Test("browseAll は TotalMatches が不正に大きい値を返し続けても最大ページ数で打ち切る")
    func browseAllAbortsOnMaxPages() async throws {
        let counter = CallCounter()
        let client = ContentDirectoryClient { request in
            counter.increment()
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let startingIndex = Self.extractStartingIndex(from: body)
            // 毎回ユニークなページを返す（同一ページ検出には引っかからない）が、
            // TotalMatches は非現実的に巨大な値を返し続ける壊れたサーバーを模す。
            return Self.responseXML(items: [("item-\(startingIndex)", "T\(startingIndex)")], total: 10_000_000)
        }
        await #expect(throws: ContentDirectoryClient.ClientError.pagingAborted) {
            _ = try await client.browseAll(
                controlURL: URL(string: "http://x/ctl")!, objectID: "0", pageSize: 1, maxPages: 5
            )
        }
        #expect(counter.count == 5)
    }

    @Test("browse() は transport 経由でレスポンスを取得し解析する")
    func browseUsesTransport() async throws {
        let data = try Self.fixture("browse_response")
        let client = ContentDirectoryClient { request in
            // SOAPAction ヘッダと URL を検証
            #expect(request.value(forHTTPHeaderField: "SOAPAction")
                == "\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"")
            #expect(request.httpMethod == "POST")
            #expect(request.url == URL(string: "http://192.168.1.10:8200/ctl/ContentDir"))
            return data
        }

        let result = try await client.browse(
            controlURL: URL(string: "http://192.168.1.10:8200/ctl/ContentDir")!,
            objectID: "0"
        )
        #expect(result.objects.count == 2)
    }
}
