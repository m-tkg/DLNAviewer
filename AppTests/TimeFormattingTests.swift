import Foundation
import Testing
@testable import DLNAviewer

@Suite("TimeFormatting")
struct TimeFormattingTests {
    @Test("1 時間未満は m:ss")
    func underOneHour() {
        #expect(TimeFormatting.timeString(0) == "0:00")
        #expect(TimeFormatting.timeString(59) == "0:59")
        #expect(TimeFormatting.timeString(3599) == "59:59")
    }

    @Test("1 時間以上は h:mm:ss")
    func overOneHour() {
        #expect(TimeFormatting.timeString(3600) == "1:00:00")
        #expect(TimeFormatting.timeString(3661) == "1:01:01")
    }

    @Test("padHours で 1 時間未満でも桁を固定する")
    func padHours() {
        #expect(TimeFormatting.timeString(65, padHours: true) == "0:01:05")
        #expect(TimeFormatting.timeString(0, padHours: true) == "0:00:00")
    }

    @Test("既定は切り捨て、rounded 指定で四捨五入")
    func rounding() {
        #expect(TimeFormatting.timeString(59.6) == "0:59")
        #expect(TimeFormatting.timeString(59.6, rounded: true) == "1:00")
    }

    @Test("非有限・負値は 0 表示に落ちる")
    func invalidValues() {
        #expect(TimeFormatting.timeString(.infinity) == "0:00")
        #expect(TimeFormatting.timeString(.nan) == "0:00")
        #expect(TimeFormatting.timeString(-5) == "0:00")
        #expect(TimeFormatting.timeString(.infinity, padHours: true) == "0:00:00")
    }
}
