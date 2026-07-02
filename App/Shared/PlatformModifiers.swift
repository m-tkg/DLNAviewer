import SwiftUI

/// iOS 専用 modifier の `#if os(iOS)` 定型を吸収するヘルパ群。macOS では何もしない。
extension View {
    /// ナビゲーションタイトルをインライン表示にする（iOS のみ有効）。
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// テキスト入力の自動大文字化を無効にする（iOS のみ有効）。
    func noAutocapitalization() -> some View {
        #if os(iOS)
        return textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }
}
