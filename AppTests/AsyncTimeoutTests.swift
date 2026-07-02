import Foundation
import Testing
@testable import DLNAviewer

@Suite("AsyncTimeout")
struct AsyncTimeoutTests {
    @Test("制限時間内に終わればその結果を返す")
    func returnsResultWhenFast() async {
        let result = await AsyncTimeout.run(seconds: 0.2) {
            42
        }
        #expect(result == 42)
    }

    @Test("制限時間を超えたら nil を返す")
    func returnsNilWhenSlow() async {
        let result = await AsyncTimeout.run(seconds: 0.05) {
            try? await Task.sleep(for: .seconds(1))
            return 42
        }
        #expect(result == nil)
    }

    @Test("タイムアウト時のみ onTimeout が呼ばれる")
    func callsOnTimeoutOnlyWhenTimedOut() async {
        final class Flag: @unchecked Sendable {
            var fired = false
        }
        let fastFlag = Flag()
        _ = await AsyncTimeout.run(seconds: 0.2, onTimeout: { fastFlag.fired = true }) {
            1
        }
        #expect(fastFlag.fired == false)

        let slowFlag = Flag()
        _ = await AsyncTimeout.run(seconds: 0.05, onTimeout: { slowFlag.fired = true }) {
            try? await Task.sleep(for: .seconds(1))
            return 1
        }
        #expect(slowFlag.fired == true)
    }
}
