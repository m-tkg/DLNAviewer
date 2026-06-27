import Foundation
import Testing
@testable import DLNAKit

@Suite("DIDLParser")
struct DIDLParserTests {
    /// テスト用フィクスチャ XML を読み込む。
    static func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("コンテナとアイテムを順序通りに解析する")
    func parsesObjectsInOrder() throws {
        let xml = try Self.fixture("browse_result")
        let objects = try DIDLParser.parse(xml)

        #expect(objects.count == 5)
        #expect(objects.map(\.title) == ["Movies", "Home Videos", "Big Buck Bunny", "Sintel", "Song & Dance"])
    }

    @Test("コンテナの属性を解析する")
    func parsesContainerAttributes() throws {
        let xml = try Self.fixture("browse_result")
        let objects = try DIDLParser.parse(xml)

        guard case .container(let movies) = objects[0] else {
            Issue.record("先頭はコンテナのはず")
            return
        }
        #expect(movies.id == "64")
        #expect(movies.parentID == "0")
        #expect(movies.title == "Movies")
        #expect(movies.childCount == 3)

        guard case .container(let homeVideos) = objects[1] else {
            Issue.record("2番目はコンテナのはず")
            return
        }
        #expect(homeVideos.childCount == nil)
    }

    @Test("動画アイテムの res 属性を解析する")
    func parsesVideoItemResource() throws {
        let xml = try Self.fixture("browse_result")
        let objects = try DIDLParser.parse(xml)

        guard case .item(let bunny) = objects[2] else {
            Issue.record("3番目はアイテムのはず")
            return
        }
        #expect(bunny.id == "64$1")
        #expect(bunny.parentID == "64")
        #expect(bunny.title == "Big Buck Bunny")
        #expect(bunny.isVideo)
        #expect(bunny.resources.count == 1)

        let res = try #require(bunny.resources.first)
        #expect(res.url == URL(string: "http://192.168.1.10:8200/MediaItems/512.mp4"))
        #expect(res.mimeType == "video/mp4")
        #expect(res.size == 158_008_374)
        #expect(res.resolution == "1280x720")
        // 0:09:56.000 = 596 秒
        #expect(res.durationSeconds == 596.0)
    }

    @Test("複数 res を持つアイテムと相対 URL の絶対化")
    func parsesMultipleResourcesAndResolvesRelativeURL() throws {
        let xml = try Self.fixture("browse_result")
        let base = URL(string: "http://192.168.1.10:8200/rootDesc.xml")!
        let objects = try DIDLParser.parse(xml, baseURL: base)

        guard case .item(let sintel) = objects[3] else {
            Issue.record("4番目はアイテムのはず")
            return
        }
        #expect(sintel.resources.count == 2)
        // 相対 URL は baseURL で絶対化される
        #expect(sintel.resources[0].url == URL(string: "http://192.168.1.10:8200/MediaItems/777.mkv"))
        #expect(sintel.resources[0].mimeType == "video/x-matroska")
        #expect(sintel.resources[1].url == URL(string: "http://192.168.1.10:8200/MediaItems/777.mp4"))
        // 0:14:48 = 888 秒
        #expect(sintel.resources[1].durationSeconds == 888.0)
    }

    @Test("albumArtURI をサムネイルとして解析する")
    func parsesAlbumArtThumbnail() throws {
        let xml = try Self.fixture("browse_result")
        let objects = try DIDLParser.parse(xml)
        guard case .item(let bunny) = objects[2] else {
            Issue.record("3番目はアイテムのはず"); return
        }
        #expect(bunny.albumArtURI == URL(string: "http://192.168.1.10:8200/Thumbnails/512.jpg"))
        #expect(bunny.thumbnailURL == URL(string: "http://192.168.1.10:8200/Thumbnails/512.jpg"))
    }

    @Test("画像 res はサムネイルに分類され、再生リソースには含めない")
    func separatesImageResourceAsThumbnail() throws {
        let xml = try Self.fixture("browse_result")
        let objects = try DIDLParser.parse(xml)
        guard case .item(let sintel) = objects[3] else {
            Issue.record("4番目はアイテムのはず"); return
        }
        // 動画 res は2本のまま（画像 res は混ざらない）
        #expect(sintel.resources.count == 2)
        #expect(sintel.resources.allSatisfy { ($0.mimeType ?? "").hasPrefix("video/") })
        // 画像 res はサムネイルへ
        #expect(sintel.thumbnails.count == 1)
        #expect(sintel.thumbnailURL == URL(string: "http://192.168.1.10:8200/Thumbnails/777.jpg"))
    }

    @Test("XML エンティティを含むタイトルを解析する")
    func decodesXMLEntitiesInTitle() throws {
        let xml = try Self.fixture("browse_result")
        let objects = try DIDLParser.parse(xml)
        #expect(objects[4].title == "Song & Dance")
    }

    @Test("不正な XML はエラーを投げる")
    func throwsOnInvalidXML() {
        #expect(throws: DIDLParser.ParseError.self) {
            _ = try DIDLParser.parse("not xml at all <<<")
        }
    }
}
