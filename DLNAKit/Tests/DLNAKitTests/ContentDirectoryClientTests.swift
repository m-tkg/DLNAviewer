import Foundation
import Testing
@testable import DLNAKit

@Suite("ContentDirectoryClient")
struct ContentDirectoryClientTests {
    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
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
