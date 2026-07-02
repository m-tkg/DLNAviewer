import SwiftUI
import DLNAKit

/// 評価（Like / Dislike / なし）を選ぶメニュー。長押し・右クリックのコンテキストメニューから使う。
struct RatingMenu: View {
    let item: MediaItem
    let ratings: RatingsModel

    var body: some View {
        Picker("評価", selection: Binding(
            get: { ratings.rating(for: item) },
            set: { ratings.set($0, for: item) }
        )) {
            Label("Like", systemImage: "hand.thumbsup").tag(Rating.like)
            Label("Dislike", systemImage: "hand.thumbsdown").tag(Rating.dislike)
            Label("評価なし", systemImage: "minus").tag(Rating.none)
        }
    }
}

/// スワイプアクション用の評価ボタン（Like / Dislike / クリア）。
struct RatingSwipeButtons: View {
    let item: MediaItem
    let ratings: RatingsModel

    var body: some View {
        Button { ratings.set(.like, for: item) } label: {
            Label("Like", systemImage: "hand.thumbsup")
        }.tint(.green)
        Button { ratings.set(.dislike, for: item) } label: {
            Label("Dislike", systemImage: "hand.thumbsdown")
        }.tint(.red)
        if ratings.rating(for: item) != .none {
            Button { ratings.set(.none, for: item) } label: {
                Label("クリア", systemImage: "xmark")
            }.tint(.gray)
        }
    }
}

/// confirmationDialog 用の評価ボタン（Picker が使えない場面向け）。
struct RatingDialogButtons: View {
    let item: MediaItem
    let ratings: RatingsModel

    var body: some View {
        Button("👍 Like") { ratings.set(.like, for: item) }
        Button("👎 Dislike") { ratings.set(.dislike, for: item) }
        if ratings.rating(for: item) != .none {
            Button("評価なし") { ratings.set(.none, for: item) }
        }
    }
}
