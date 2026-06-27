import SwiftUI

/// アプリ設定。
struct SettingsView: View {
    @AppStorage("seekUnitTop") private var seekUnitTop = 60
    @AppStorage("seekUnitBottom") private var seekUnitBottom = 30
    @AppStorage("thumbnailSize") private var thumbnailSize = 1   // 0=小, 1=中, 2=大
    @Environment(\.dismiss) private var dismiss

    private let options = [5, 10, 15, 30, 45, 60, 90, 120, 180, 300]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("上半分のスワイプ", selection: $seekUnitTop) {
                        ForEach(options, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                    Picker("下半分のスワイプ", selection: $seekUnitBottom) {
                        ForEach(options, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                } header: {
                    Text("スワイプシークの単位")
                } footer: {
                    Text("再生画面でコントロール非表示のとき、画面の上半分／下半分を左右スワイプした 1 単位あたりの秒数です。")
                }

                Section("表示") {
                    Picker("サムネイルのサイズ", selection: $thumbnailSize) {
                        Text("小").tag(0)
                        Text("中").tag(1)
                        Text("大").tag(2)
                    }
                    #if os(iOS)
                    .pickerStyle(.segmented)
                    #endif
                }
            }
            .navigationTitle("設定")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    static func label(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)秒" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m)分" : "\(m)分\(s)秒"
    }
}
