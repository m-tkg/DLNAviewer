#if os(iOS)
import SwiftUI
import UIKit
import VisionKit
import Vision

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

// MARK: - 顔で俳優を検索

/// Vision で顔を検出するヘルパー。
enum FaceFinder {
    /// 画像内の顔を検出し、面積の大きい順（上限 8 件）に画像ピクセル座標の矩形で返す。
    static func faces(in image: UIImage) async -> [CGRect] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
                try? handler.perform([request])
                let w = CGFloat(cg.width), h = CGFloat(cg.height)
                // Vision の boundingBox は正規化・左下原点なので、ピクセル・左上原点へ変換。
                let rects = (request.results ?? []).map { obs -> CGRect in
                    let bb = obs.boundingBox
                    return CGRect(x: bb.minX * w, y: (1 - bb.maxY) * h,
                                  width: bb.width * w, height: bb.height * h)
                }
                let sorted = rects.sorted { $0.width * $0.height > $1.width * $1.height }
                continuation.resume(returning: Array(sorted.prefix(8)))
            }
        }
    }
}

/// 顔矩形に余白を足して切り出すヘルパー。
enum FaceCropper {
    /// 顔の周囲に `paddingRatio` 分の余白（髪・輪郭）を足して切り出す。検索精度が上がる。
    static func crop(_ image: UIImage, to faceRect: CGRect, paddingRatio: CGFloat = 0.5) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))
        let rect = faceRect
            .insetBy(dx: -faceRect.width * paddingRatio, dy: -faceRect.height * paddingRatio)
            .intersection(bounds)
        guard !rect.isNull, let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}

/// 顔候補（複数人時のシート提示用）。
struct FaceCandidates: Identifiable {
    let id = UUID()
    let image: UIImage
    let faces: [CGRect]
}

/// 複数の顔から検索したい 1 人を選ばせるシート。選んだ顔を共有（Google Lens 等）へ。
struct FacePickerView: View {
    let image: UIImage
    let thumbs: [UIImage]
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: CapturedImage?

    init(image: UIImage, faces: [CGRect]) {
        self.image = image
        self.thumbs = faces.map { FaceCropper.crop(image, to: $0) ?? image }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("検索したい人物の顔を選んでください")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(thumbs.indices, id: \.self) { i in
                        Button {
                            shareItem = CapturedImage(image: thumbs[i])
                        } label: {
                            Image(uiImage: thumbs[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                // 顔を選ばずフレーム全体で検索したい場合。
                Button {
                    shareItem = CapturedImage(image: image)
                } label: {
                    Label("全体で検索", systemImage: "rectangle.dashed")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            .navigationTitle("顔を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { captured in
                ShareSheet(items: [captured.image])
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
