import Foundation

/// 永続化ストア群の共通コア。「lock → load → 操作 → save」の骨格を一元化する。
///
/// 各ストアは値の型（辞書や配列）とドメイン操作だけを持ち、読み書きは
/// `read` / `mutate` に委譲する。値は `KeyValueStorage` の 1 キーに JSON で保存する。
/// CloudSync が UserDefaults を直接書き換えるため、メモリにキャッシュせず毎回
/// storage から読み直す。
///
/// - Note: `body` の中から同じコアの `read`/`mutate` を呼ぶと NSLock でデッドロック
///   する。ストアの公開メソッドから別の公開メソッドを呼ばないこと。
final class JSONStoreCore<Value: Codable>: @unchecked Sendable {
    private let storage: KeyValueStorage
    private let key: String
    private let lock = NSLock()
    private let makeDefault: @Sendable () -> Value

    init(storage: KeyValueStorage, key: String, default makeDefault: @escaping @Sendable () -> Value) {
        self.storage = storage
        self.key = key
        self.makeDefault = makeDefault
    }

    /// 現在値を読み取って `body` に渡す。
    func read<R>(_ body: (Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(load())
    }

    /// 現在値を `body` で変更し、保存する。
    @discardableResult
    func mutate<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        var value = load()
        let result = body(&value)
        save(value)
        return result
    }

    // MARK: - 内部

    private func load() -> Value {
        guard let data = storage.data(forKey: key),
              let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return makeDefault()
        }
        return value
    }

    private func save(_ value: Value) {
        storage.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
