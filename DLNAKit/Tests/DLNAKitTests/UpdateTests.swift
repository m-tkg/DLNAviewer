import Foundation
import Testing
@testable import DLNAKit

@Suite("VersionComparator")
struct VersionComparatorTests {
    @Test("新しいタグを検出（v プレフィックスあり）")
    func newer() {
        #expect(VersionComparator.isNewer(tag: "v1.1", than: "1.0"))
        #expect(VersionComparator.isNewer(tag: "v2.0", than: "1.9"))
        #expect(VersionComparator.isNewer(tag: "v1.0.1", than: "1.0"))
    }

    @Test("同一・古いタグは false")
    func notNewer() {
        #expect(!VersionComparator.isNewer(tag: "v1.0", than: "1.0"))
        #expect(!VersionComparator.isNewer(tag: "v1.0", than: "1.1"))
        #expect(!VersionComparator.isNewer(tag: "1.0", than: "1.0.0"))
    }

    @Test("数値として比較（文字列比較ではない）")
    func numericCompare() {
        #expect(VersionComparator.isNewer(tag: "v1.10", than: "1.9"))
        #expect(!VersionComparator.isNewer(tag: "v1.9", than: "1.10"))
    }

    @Test("非数値サフィックスは先頭の数字のみ採用")
    func nonNumericSuffix() {
        #expect(VersionComparator.isNewer(tag: "v1.2-beta", than: "1.1"))
        #expect(!VersionComparator.isNewer(tag: "v1.0-beta", than: "1.0"))
    }
}

@Suite("ReleaseInfo")
struct ReleaseInfoTests {
    private let json = """
    {
      "tag_name": "v1.2",
      "html_url": "https://github.com/m-tkg/DLNAviewer/releases/tag/v1.2",
      "assets": [
        {"name": "DLNAviewer.zip", "browser_download_url": "https://example.com/DLNAviewer.zip"},
        {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"}
      ]
    }
    """

    @Test("GitHub レスポンスをデコード")
    func decode() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        #expect(release.tagName == "v1.2")
        #expect(release.assets.count == 2)
    }

    @Test("zip アセットの URL を取得")
    func zipURL() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        #expect(release.zipAssetURL == URL(string: "https://example.com/DLNAviewer.zip"))
    }

    @Test("assets 欠落でもデコードでき zip は nil")
    func missingAssets() throws {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(#"{"tag_name":"v1.0","html_url":"x"}"#.utf8))
        #expect(release.assets.isEmpty)
        #expect(release.zipAssetURL == nil)
    }
}
