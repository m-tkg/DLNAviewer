import Testing
import Foundation
@testable import DLNAKit

@Suite("OrphanDetector")
struct OrphanDetectorTests {
    @Test("live に無いキーだけが種類別に孤立になる")
    func detectsOrphansByKind() {
        let live: Set<String> = ["A", "B"]
        let report = OrphanDetector.detect(
            live: live,
            ratingKeys: ["A", "X"],     // X は live に無い → 孤立
            bookmarkKeys: ["B"],         // すべて live → 孤立なし
            tagKeys: ["Y"],              // Y → 孤立
            thumbnailKeys: ["A", "Z"],   // Z → 孤立
            downloadKeys: ["W"]          // W → 孤立
        )
        #expect(report.ratings == ["X"])
        #expect(report.bookmarks == [])
        #expect(report.tags == ["Y"])
        #expect(report.thumbnails == ["Z"])
        #expect(report.downloads == ["W"])
        #expect(report.total == 4)
    }

    @Test("すべて live にあれば孤立は 0")
    func noOrphansWhenAllLive() {
        let live: Set<String> = ["A", "B", "C"]
        let report = OrphanDetector.detect(
            live: live,
            ratingKeys: ["A"],
            bookmarkKeys: ["B"],
            tagKeys: ["C"],
            thumbnailKeys: [],
            downloadKeys: ["A", "B"]
        )
        #expect(report.total == 0)
    }
}
