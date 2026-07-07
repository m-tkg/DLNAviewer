import SwiftUI

/// `swipeActions`／`contextMenu` で使う1操作の定義。
struct RowAction: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let isDestructive: Bool
    let action: () -> Void

    init(_ label: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }

    @ViewBuilder
    var button: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            Label(label, systemImage: systemImage)
        }
        .tint(isDestructive ? nil : .blue)
    }
}

extension View {
    /// 同じ操作群を swipeActions（iOS のスワイプ）と contextMenu（macOS の右クリック／iOS の長押し）
    /// の両方に適用する。並び順・文言はそれぞれの慣習に合わせて個別に渡す。
    func rowActions(swipe: [RowAction], context: [RowAction]) -> some View {
        self
            .swipeActions {
                ForEach(swipe) { $0.button }
            }
            .contextMenu {
                ForEach(context) { $0.button }
            }
    }
}
