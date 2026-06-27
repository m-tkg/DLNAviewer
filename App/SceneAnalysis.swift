#if os(iOS)
import SwiftUI
import UIKit
import VisionKit

/// シート提示用に UIImage を識別可能にするラッパ。
struct CapturedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// UIActivityViewController（共有シート）。画像検索（Google 等）・保存などに使う。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// シーン画像を VisionKit で解析（Visual Look Up / Live Text）して表示する。
struct SceneAnalysisView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            LiveTextImageView(image: image)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("このシーン")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { sharing = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完了") { dismiss() }
                    }
                }
                .sheet(isPresented: $sharing) {
                    ShareSheet(items: [image])
                }
        }
    }
}

/// 画像を表示し、VisionKit の解析（Live Text ＋ Visual Look Up）を有効にするビュー。
private struct LiveTextImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(context.coordinator.interaction)
        context.coordinator.analyze(image)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        let interaction = ImageAnalysisInteraction()
        private let analyzer = ImageAnalyzer()

        func analyze(_ image: UIImage) {
            Task {
                let configuration = ImageAnalyzer.Configuration([.text, .visualLookUp])
                guard let analysis = try? await analyzer.analyze(image, configuration: configuration) else { return }
                interaction.analysis = analysis
                interaction.preferredInteractionTypes = .automatic
            }
        }
    }
}
#endif
