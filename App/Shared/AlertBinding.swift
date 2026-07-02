import SwiftUI

extension Binding where Value == Bool {
    /// optional な状態変数を alert / sheet の `isPresented` に変換する。
    /// 表示は「nil でないこと」、閉じたら元の変数を nil に戻す。
    init<Wrapped>(presenting source: Binding<Wrapped?>) {
        self.init(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}
