import SwiftUI
import DLNAKit

/// 画面中央に出すフィードバック（評価変更時のアイコン演出）。
struct FeedbackItem: Equatable {
    let id: UUID
    let rating: Rating
}

/// 評価変更などのフィードバック演出をトリガーする。
@MainActor
@Observable
final class FeedbackCenter {
    static let shared = FeedbackCenter()
    private(set) var current: FeedbackItem?

    /// 評価アイコンを画面中央でフラッシュさせる（none は演出なし）。
    func flash(_ rating: Rating) {
        guard rating != .none else { return }
        current = FeedbackItem(id: UUID(), rating: rating)
    }
}

/// 当たり判定を持たない、画面中央のフィードバック用オーバーレイ。
struct RatingFeedbackOverlay: View {
    var body: some View {
        ZStack {
            if let item = FeedbackCenter.shared.current {
                FlashIcon(rating: item.rating)
                    .id(item.id)   // 新しいフラッシュごとに作り直してアニメ再生
            }
        }
        .allowsHitTesting(false)   // タップはその下へ素通り
    }
}

/// 出現後に小さくなりながら消えるアイコン。
private struct FlashIcon: View {
    let rating: Rating
    @State private var animate = false

    var body: some View {
        Image(systemName: rating == .like ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
            .font(.system(size: 130))
            .foregroundStyle(rating == .like ? Color.green : Color.red)
            .shadow(color: .black.opacity(0.4), radius: 8)
            .scaleEffect(animate ? 0.3 : 1.0)
            .opacity(animate ? 0 : 0.95)
            .onAppear {
                withAnimation(.easeOut(duration: 0.65)) { animate = true }
            }
    }
}
