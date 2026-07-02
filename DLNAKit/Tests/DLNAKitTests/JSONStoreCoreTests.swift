import Foundation
import Testing
@testable import DLNAKit

@Suite("JSONStoreCore")
struct JSONStoreCoreTests {
    private func makeCore(storage: KeyValueStorage = InMemoryStorage()) -> JSONStoreCore<[String: Double]> {
        JSONStoreCore(storage: storage, key: "test", default: { [:] })
    }

    @Test("未保存なら既定値を返す")
    func returnsDefaultWhenEmpty() {
        let core = makeCore()
        #expect(core.read { $0 } == [:])
    }

    @Test("mutate した値が別インスタンスからも読める")
    func persistsAcrossInstances() {
        let storage = InMemoryStorage()
        makeCore(storage: storage).mutate { $0["a"] = 1 }
        #expect(makeCore(storage: storage).read { $0 } == ["a": 1])
    }

    @Test("mutate の戻り値が伝播する")
    func mutateReturnsResult() {
        let core = makeCore()
        let old: Double? = core.mutate { value in
            defer { value["a"] = 2 }
            return value["a"]
        }
        #expect(old == nil)
        #expect(core.read { $0["a"] } == 2)
    }

    @Test("壊れたデータは既定値に落ちる")
    func corruptDataFallsBackToDefault() {
        let storage = InMemoryStorage()
        storage.set(Data("not json".utf8), forKey: "test")
        #expect(makeCore(storage: storage).read { $0 } == [:])
    }

    @Test("エンコード失敗時は既存データを消さない")
    func encodeFailureKeepsExistingData() {
        let storage = InMemoryStorage()
        let core = makeCore(storage: storage)
        core.mutate { $0["a"] = 1 }

        // 非有限値は JSONEncoder が既定で encode に失敗する。
        core.mutate { $0["bad"] = .infinity }

        #expect(core.read { $0 } == ["a": 1], "エンコードに失敗した書き込みで既存データが消えてはならない")
    }
}
