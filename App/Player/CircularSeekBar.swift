#if os(iOS)
import SwiftUI

/// 現在位置を**丸いサム**で示すシークバー（標準 `Slider` の幅広サムを置換）。
/// `Slider` 同様に `onEditingChanged` でスクラブの開始/終了を通知し、
/// ブックマーク位置（黄色）も重ねて表示する。タップ／ドラッグでシーク。
struct CircularSeekBar: View {
    @Binding var value: Double
    let duration: Double
    let bookmarks: [Double]
    var onEditingChanged: (Bool) -> Void

    @State private var editing = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let total = max(duration, 0.1)
            let frac = CGFloat(min(max(value / total, 0), 1))
            let thumb: CGFloat = 14
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                Capsule().fill(.white).frame(width: width * frac, height: 4)
                ForEach(bookmarks, id: \.self) { time in
                    let f = duration > 0 ? CGFloat(min(max(time / duration, 0), 1)) : 0
                    Capsule().fill(.yellow).frame(width: 3, height: 12)
                        .offset(x: width * f - 1.5)
                }
                Circle().fill(.white).frame(width: thumb, height: thumb)
                    .offset(x: width * frac - thumb / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !editing { editing = true; onEditingChanged(true) }
                        let x = min(max(g.location.x, 0), width)
                        value = Double(x / width) * total
                    }
                    .onEnded { _ in
                        editing = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 24)
    }
}
#endif
