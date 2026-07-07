import SwiftUI

/// DLNA サーバーの記述 URL 入力欄＋エラー表示。AddServerView / EditServerView で共通利用する。
struct ServerURLField: View {
    @Binding var urlString: String
    let error: String?

    var body: some View {
        TextField("http://192.168.1.10:8200/rootDesc.xml", text: $urlString)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
}
