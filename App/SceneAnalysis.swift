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
    @State private var description: String?
    @State private var isDescribing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LiveTextImageView(image: image)
                    .background(Color.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    // Foundation Models（オンデバイス）によるシーン説明
                    if SceneDescriber.isAvailable {
                        sceneDescriptionSection
                    }

                    // 一般的な画像検索は共有（Google Lens 等）で。
                    Button {
                        sharing = true
                    } label: {
                        Label("画像で検索（Google Lens 等）", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("被写体（建物・植物・動物・作品・料理など）は画像内のⓘや長押しで「調べる」。一般的な検索は上のボタンから。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
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

    @ViewBuilder
    private var sceneDescriptionSection: some View {
        if let description {
            ScrollView {
                Text(description)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        } else {
            Button {
                Task {
                    isDescribing = true
                    description = await SceneDescriber.describe(image)
                    isDescribing = false
                }
            } label: {
                if isDescribing {
                    HStack { ProgressView(); Text("シーンを解析中…") }
                        .frame(maxWidth: .infinity)
                } else {
                    Label("シーンを説明（AI）", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isDescribing)
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
        // 内在サイズで広がって下のボタンを押し出さないよう、縮小を許可する。
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        let interaction = context.coordinator.interaction
        interaction.preferredInteractionTypes = .automatic
        imageView.addInteraction(interaction)
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
            guard ImageAnalyzer.isSupported else { return }
            Task {
                let configuration = ImageAnalyzer.Configuration([.text, .visualLookUp, .machineReadableCode])
                guard let analysis = try? await analyzer.analyze(image, configuration: configuration) else { return }
                interaction.analysis = analysis
                interaction.preferredInteractionTypes = .automatic
            }
        }
    }
}
#endif
