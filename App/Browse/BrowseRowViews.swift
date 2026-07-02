import SwiftUI
import DLNAKit

/// 検索フォームのタグトークン。
struct TagToken: Identifiable, Hashable {
    var id: String { name }
    let name: String
}

/// 動画アイテム 1 行。
struct VideoRow: View {
    let item: MediaItem
    let rating: Rating
    var thumbSize: CGSize = CGSize(width: 68, height: 38)

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                ZStack(alignment: .topLeading) {
                    ThumbnailView(item: item, size: thumbSize)
                    // ブックマークがある動画は左上にアイコン表示。
                    if !BookmarksModel.shared.bookmarks(for: item).isEmpty {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .shadow(radius: 1)
                            .padding(3)
                    }
                }
                // ダウンロード中はサムネの下にプログレスバー。
                if case .downloading(let progress) = DownloadManager.shared.state(for: item) {
                    ProgressView(value: progress)
                        .frame(width: thumbSize.width)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                let tags = TagsModel.shared.tags(for: item)
                if !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if DownloadManager.shared.state(for: item).isDownloaded {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if rating != .none {
                Image(systemName: rating.symbol)
                    .foregroundStyle(rating == .like ? .green : .red)
            }
        }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let res = item.preferredVideoResource {
            if let seconds = res.durationSeconds {
                parts.append(TimeFormatting.timeString(seconds, rounded: true))
            }
            if let resolution = res.resolution {
                parts.append(resolution)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

}

/// タイルのサムネ左下用。タグを横一列に詰め、入りきらない分は "…" で省略する。
struct TagOverflowRow: View {
    let tags: [String]

    var body: some View {
        TagOverflowLayout(spacing: 3) {
            ForEach(tags, id: \.self) { tag in
                chip(tag, color: AnyShapeStyle(.tint.opacity(0.85)))
            }
            // 省略インジケータ。レイアウト側が必要なときだけ配置する（最後の subview）。
            chip("…", color: AnyShapeStyle(.black.opacity(0.55)))
        }
    }

    private func chip(_ text: String, color: AnyShapeStyle) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color, in: Capsule())
    }
}

/// 横一列にタグを詰め、入りきらなければ末尾の subview（"…"）だけ残して省略するレイアウト。
/// subviews の最後を省略インジケータと見なす。全タグが収まるときは "…" を配置しない。
struct TagOverflowLayout: Layout {
    var spacing: CGFloat = 3

    private struct Plan { var sizes: [CGSize]; var visible: [Int]; var width: CGFloat; var height: CGFloat }

    private func plan(_ subviews: Subviews, maxWidth: CGFloat) -> Plan {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0
        guard subviews.count >= 2 else {
            return Plan(sizes: sizes, visible: Array(0..<subviews.count), width: width(of: Array(0..<subviews.count), sizes), height: height)
        }
        let ellipsis = subviews.count - 1            // 末尾は "…"
        let tagIndices = Array(0..<ellipsis)
        // 全タグが収まるなら "…" 無しで全部出す。
        let allWidth = width(of: tagIndices, sizes)
        if allWidth <= maxWidth {
            return Plan(sizes: sizes, visible: tagIndices, width: allWidth, height: height)
        }
        // 収まらないので "…" の幅を確保しつつ、入る分だけ詰める。
        let ellipsisWidth = sizes[ellipsis].width
        var used: CGFloat = 0
        var visible: [Int] = []
        for i in tagIndices {
            let add = (visible.isEmpty ? 0 : spacing) + sizes[i].width
            if used + add + spacing + ellipsisWidth <= maxWidth {
                used += add
                visible.append(i)
            } else {
                break
            }
        }
        visible.append(ellipsis)
        return Plan(sizes: sizes, visible: visible, width: width(of: visible, sizes), height: height)
    }

    private func width(of indices: [Int], _ sizes: [CGSize]) -> CGFloat {
        guard !indices.isEmpty else { return 0 }
        return indices.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(indices.count - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let p = plan(subviews, maxWidth: maxW)
        return CGSize(width: min(p.width, maxW), height: p.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(subviews, maxWidth: bounds.width)
        let visibleSet = Set(p.visible)
        var x = bounds.minX
        for i in p.visible {
            let size = p.sizes[i]
            subviews[i].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
        // 非表示の subview は 0 サイズで隅へ寄せて描画させない。
        for i in subviews.indices where !visibleSet.contains(i) {
            subviews[i].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .leading, proposal: .zero)
        }
    }
}
