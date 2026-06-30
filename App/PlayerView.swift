import SwiftUI
import AVKit
import AVFoundation
import DLNAKit
#if os(iOS)
import Combine
import UIKit
#endif

/// 動画再生画面。
///
/// iOS は自前のコントロール（再生/停止/シーク）とタイトルを 1 つのオーバーレイにまとめ、
/// 「コントロール表示中だけタイトルも表示」を満たす。macOS は標準の `VideoPlayer` を使う。
struct PlayerView: View {
    let items: [MediaItem]
    let startIndex: Int

    private var safeIndex: Int { min(max(startIndex, 0), max(items.count - 1, 0)) }

    var body: some View {
        #if os(iOS)
        iOSPlayer(items: items, startIndex: safeIndex)
        #else
        MacPlayer(item: items[safeIndex])
        #endif
    }
}

/// 評価（Like / Dislike / なし）を選ぶメニュー。長押し・右クリックから使う。
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

// MARK: - macOS

#if os(macOS)
private struct MacPlayer: View {
    let item: MediaItem
    @Environment(RatingsModel.self) private var ratings
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
                    .contextMenu { RatingMenu(item: item, ratings: ratings) }
            } else {
                ContentUnavailableView(
                    "再生できません",
                    systemImage: "play.slash",
                    description: Text("このアイテムには再生可能なリソースがありません。")
                )
            }
        }
        .navigationTitle(item.title)
        .onAppear {
            guard player == nil, let url = DownloadManager.shared.preferredURL(for: item) else { return }
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 0
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = false
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
#endif

// MARK: - iOS

#if os(iOS)
private struct iOSPlayer: View {
    let items: [MediaItem]
    @State private var index: Int

    init(items: [MediaItem], startIndex: Int) {
        self.items = items
        _index = State(initialValue: startIndex)
    }

    /// 現在の動画。
    private var item: MediaItem { items[index] }

    @Environment(\.dismiss) private var dismiss
    @Environment(RatingsModel.self) private var ratings

    /// サイレントモードでも音を出すか（オフ＝サイレント尊重）。端末に永続化。
    @AppStorage("playInSilentMode") private var playInSilentMode = false
    /// 上半分／下半分のスワイプ 1 単位あたりの秒数（設定で変更）。
    @AppStorage("seekUnitTop") private var seekUnitTop = 60
    @AppStorage("seekUnitBottom") private var seekUnitBottom = 30
    /// 戻る/進むボタンの秒数、ダブルタップの秒数（設定で変更）。
    @AppStorage("skipSeconds") private var skipSeconds = 10
    @AppStorage("doubleTapSeconds") private var doubleTapSeconds = 30
    /// 再生速度（倍率）。好みの速度を端末に永続化し、次回・次アイテムへ引き継ぐ。
    @AppStorage("playbackRate") private var playbackRate = 1.0

    /// 速度メニューのプリセット。
    private static let speedOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    // 再生・PiP・描画レイヤーは永続モデルが保持する（画面遷移をまたいで継続）。
    private var player: AVPlayer { PlaybackModel.shared.player }
    private var pip: PiPController { PlaybackModel.shared.pip }

    @State private var hasSource = true
    @State private var controlsVisible = true
    @State private var isPlaying = true
    // 再生待ち（バッファ読み込み中）。true の間はコントロールを隠してスピナーを出す。
    @State private var isWaiting = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var hideTask: Task<Void, Never>?
    @State private var showingBookmarks = false
    // シーク中の音声再生用
    @State private var scrubAudioActive = false
    @State private var wasPlayingBeforeScrub = false
    // シーク中だけスタール待機を有効化し、再生が安定したら元（待たない＝即時再生）へ戻す予約。
    @State private var restoreStallWaitingWhenPlaying = false

    // スワイプシーク用
    @State private var viewHeight: CGFloat = 1
    // ダブルタップスキップのヒント表示
    @State private var doubleTapHint: (forward: Bool, seconds: Int)?
    @State private var hintTask: Task<Void, Never>?
    // ダブルタップ＋長押し中の 2 倍速再生
    @State private var fastForwarding = false
    @State private var showingActionMenu = false
    // 現在シーンの解析・画像検索
    @State private var analysisImage: CapturedImage?
    @State private var shareImage: CapturedImage?
    @State private var showingTagEditor = false
    @State private var showingFullTitle = false
    @State private var dragStartTime: Double?
    @State private var dragUnit: Double = 60
    @State private var pendingSeekTarget: Double?
    @State private var seeker = SmoothSeeker()

    /// 縦スワイプで回転とみなす最小移動量。
    private let rotateThreshold: CGFloat = 60

    /// 横ドラッグ何ポイントで 1 単位進めるか。
    private let pointsPerUnit: CGFloat = 30

    // @State で 1 度だけ生成し、View 値の再生成でタイマーを作り直さない。
    @State private var ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if showingBookmarks {
                bookmarkSplitLayout
            } else {
                fullPlayer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(ticker) { _ in tick() }
        // シークバー（スライダー）ドラッグ中も動画を追従させる。
        .onChange(of: currentTime) { _, newValue in
            if isScrubbing { seeker.seek(toSeconds: newValue, tolerance: 0.5) }
        }
        // 前/次の動画へ移動したら読み込み直す。
        .onChange(of: index) { _, _ in
            currentTime = 0
            duration = 0
            pendingSeekTarget = nil
            isScrubbing = false
            hasSource = true
            isWaiting = true
            setUp()
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
        }
        .onAppear {
            // インライン表示に入るので PiP は止める（別動画を選んだ場合も旧 PiP を停止）。
            if pip.isActive { pip.stop() }
            // PiP 開始時は再生カテゴリへ、終了時はユーザー設定へ戻す。
            pip.onWillStart = { AudioSessionManager.configure(playInSilentMode: true) }
            pip.onDidStop = { AudioSessionManager.configure(playInSilentMode: playInSilentMode) }
            setUp()
            OrientationManager.shared.allowAll()   // プレイヤーは回転可能に
        }
        .onDisappear {
            hideTask?.cancel()
            OrientationManager.shared.resetToPortrait()   // 一覧へ戻る時は縦
            // PiP 中は止めない（PiP のままリストへ戻っても再生継続）。
            PlaybackModel.shared.pauseUnlessPiP()
            if !pip.isActive { AudioSessionManager.deactivate() }
        }
    }

    /// 全画面プレイヤー。
    private var fullPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if hasSource {
                PlayerLayerView().ignoresSafeArea()
                // タップ/スワイプ/長押しはこの層が一手に引き受ける（コントロールの下に常設）。
                // 中央のタッチ操作（タップ／ダブルタップ／ダブルタップ長押し2倍速／長押しメニュー／
                // スワイプシーク）を UIKit の認識器でまとめて処理する。SwiftUI のジェスチャー合成では
                // ダブルタップ長押しの判定が安定しないため。
                GestureSurface(
                    onSingleTap: { handleSingleTap() },
                    onDoubleTap: { forward in handleDoubleTap(forward: forward) },
                    onFastForwardStart: { engageFastForward() },
                    onFastForwardEnd: { disengageFastForward() },
                    onMenu: { showingActionMenu = true },
                    onPanChanged: { translation, start, size in handlePanChanged(translation: translation, startLocation: start, viewSize: size) },
                    onPanEnded: { translation in handlePanEnded(translation: translation) }
                )
                .ignoresSafeArea()
                // コントロール表示中はこの上にバーを重ねる。バー領域はタップを吸収し、
                // 中央の空き領域だけ下の tapLayer に通す。
                if isWaiting {
                    // 読み込み中はヘッダ（戻る・タイトル）だけ出し、中央にくるくるを表示。
                    VStack(spacing: 0) {
                        headerBar
                        Spacer(minLength: 0)
                    }
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .allowsHitTesting(false)   // くるくるの上の長押しを下の tapLayer に通す
                } else if controlsVisible {
                    controlsOverlay.transition(.opacity)
                }
            } else {
                ContentUnavailableView(
                    "再生できません",
                    systemImage: "play.slash",
                    description: Text("このアイテムには再生可能なリソースがありません。")
                )
                .foregroundStyle(.white)
            }

            // スワイプシーク中、コントロール非表示なら本来のシークバー（bottomBar）を同じ位置に表示。
            // コントロール表示中は既存の bottomBar が currentTime に追従するため不要。
            if pendingSeekTarget != nil && !controlsVisible {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bottomBar
                        .background {
                            LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                           startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea(edges: .bottom)
                        }
                }
                .allowsHitTesting(false)
            }

            // 2 倍速再生中のインジケータ
            if fastForwarding {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("4x").font(.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.top, 60)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // ダブルタップスキップのヒント
            if let hint = doubleTapHint {
                HStack {
                    if !hint.forward { doubleTapHintLabel(hint) }
                    Spacer()
                    if hint.forward { doubleTapHintLabel(hint) }
                }
                .padding(.horizontal, 40)
            }
        }
        .contentShape(Rectangle())
        .confirmationDialog("操作", isPresented: $showingActionMenu, titleVisibility: .hidden) {
            actionMenuButtons
        } message: {
            if isWaiting { Text(loadStatusText) }
        }
        .background {
            // 上半分／下半分の判定に使うビュー高さを取得。
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in viewHeight = h }
            }
        }
        .sheet(item: $analysisImage) { captured in
            SceneAnalysisView(image: captured.image)
        }
        .sheet(isPresented: $showingTagEditor) {
            TagEditorView(item: item)
        }
        .sheet(item: $shareImage) { captured in
            ShareSheet(items: [captured.image])
        }
        .statusBarHidden(!controlsVisible)
    }

    /// 現在の再生位置のフレームを高解像度で取得。
    private func captureFrame() async -> UIImage? {
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return nil }
        let t = player.currentTime().seconds
        let seconds = t.isFinite ? t : currentTime
        guard let cg = await ThumbnailCache.shared.generate(from: url, at: seconds, tolerance: 0.5, maxSize: 1280) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    /// ブックマーク一覧モード：上に一覧、画面下に動画（小窓）。
    private var bookmarkSplitLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ブックマーク").font(.headline)
                Spacer()
                Button { showingBookmarks = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            bookmarkList

            // 画面下に動画（小窓）＋現在位置のシークバー。
            VStack(spacing: 4) {
                ZStack {
                    Color.black
                    if hasSource { PlayerLayerView() }
                    // 左右タップで指定秒数（ダブルタップ秒数）だけ移動。
                    HStack(spacing: 0) {
                        miniTapZone(forward: false)
                        miniTapZone(forward: true)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                miniSeekBar
            }
            .background(.black)
        }
    }

    private var bookmarkList: some View {
        let marks = BookmarksModel.shared.bookmarks(for: item)
        return Group {
            if marks.isEmpty {
                ContentUnavailableView("ブックマークがありません", systemImage: "bookmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(marks, id: \.self) { time in
                        Button { seekTo(time) } label: {
                            HStack(spacing: 12) {
                                SceneThumbnailView(item: item, time: time, size: CGSize(width: 100, height: 56))
                                Text(timeLabel(time)).font(.body.monospacedDigit())
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())   // 行全体をタップ領域に
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                BookmarksModel.shared.remove(time, for: item)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 小窓用のコンパクトなシークバー（ブックマークマーカー付き）。
    private var miniSeekBar: some View {
        HStack(spacing: 8) {
            Text(Self.timeString(currentTime, padHours: duration >= 3600)).font(.caption2.monospacedDigit()).foregroundStyle(.white)
            CircularSeekBar(value: $currentTime, duration: duration,
                            bookmarks: BookmarksModel.shared.bookmarks(for: item)) { editing in
                isScrubbing = editing
                if editing {
                    beginScrub()
                } else {
                    seeker.seek(toSeconds: currentTime, tolerance: 0)
                    endScrub()
                }
            }
            Text(Self.timeString(duration, padHours: duration >= 3600)).font(.caption2.monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: コントロールオーバーレイ

    /// 長押しメニュー（評価・サムネ設定・シーン解析）。confirmationDialog に出す。
    @ViewBuilder
    private var actionMenuButtons: some View {
        Button("👍 Like") { ratings.set(.like, for: item) }
        Button("👎 Dislike") { ratings.set(.dislike, for: item) }
        if ratings.rating(for: item) != .none {
            Button("評価なし") { ratings.set(.none, for: item) }
        }
        Button("このシーンをサムネイルにする") {
            let time = player.currentTime().seconds
            if time.isFinite { ThumbnailsModel.shared.set(time, for: item) }
        }
        Button("タグを編集…") {
            pausePlayback()
            showingTagEditor = true
        }
        Button("このシーンを調べる") {
            pausePlayback()
            Task { if let image = await captureFrame() { analysisImage = CapturedImage(image: image) } }
        }
        Button("このシーンを画像検索…") {
            pausePlayback()
            Task { if let image = await captureFrame() { shareImage = CapturedImage(image: image) } }
        }
    }

    /// 再生待ち中に長押しメニューへ出す、その時点のロード状況。
    private var loadStatusText: String {
        guard let item = player.currentItem else { return "準備中…" }
        switch item.status {
        case .failed: return "読み込みに失敗しました"
        case .unknown: return "サーバに接続中…"
        case .readyToPlay:
            if item.isPlaybackLikelyToKeepUp { return "まもなく再生します" }
            let ahead = bufferedAheadSeconds(item)
            return ahead > 0
                ? String(format: "バッファリング中… 約%.0f秒先まで読み込み", ahead)
                : "バッファリング中…"
        @unknown default: return "読み込み中…"
        }
    }

    /// 現在位置から先にバッファ済みの秒数。
    private func bufferedAheadSeconds(_ item: AVPlayerItem) -> Double {
        guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return 0 }
        return max(0, CMTimeGetSeconds(range.end) - currentTime)
    }

    /// ヘッダ（戻る・タイトル・タグ）。読み込み中とコントロール表示中の両方で出す。
    private var headerBar: some View {
        VStack(spacing: 0) {
            topBar
            tagBar
        }
        .background {
            LinearGradient(colors: [.black.opacity(0.6), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
        .contentShape(Rectangle())
        .foregroundStyle(.white)
    }

    private var controlsOverlay: some View {
        // バー領域（上下）はタップを吸収してコントロールを維持。中央の空き領域だけ
        // 下の tapLayer に通し、ダブルタップスキップ／シングルタップで非表示を効かせる。
        VStack(spacing: 0) {
            headerBar

            Spacer(minLength: 0)
            centerControls
            Spacer(minLength: 0)

            bottomBar
                .background {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
                .contentShape(Rectangle())
        }
        .foregroundStyle(.white)
    }

    /// この動画に設定されたタグをすべて表示。
    @ViewBuilder
    private var tagBar: some View {
        let tags = TagsModel.shared.tags(for: item)
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 6)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                // pop より前に確定的に縦へ戻す（一覧が横で一瞬出るのを防ぐ）。
                OrientationManager.shared.resetToPortrait()
                dismiss()
            } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            Text(item.title)
                .font(.headline)
                .lineLimit(1)
                // 長押しでタイトル全文を下に表示（離すと消える）。表示中はコントロールを消さない。
                .onLongPressGesture(minimumDuration: 0.3) {
                    showingFullTitle = true
                    hideTask?.cancel()   // 表示中は自動非表示を止める
                } onPressingChanged: { pressing in
                    if !pressing {
                        showingFullTitle = false
                        scheduleAutoHide()   // 離したら自動非表示を再開
                    }
                }
            Spacer()
            // 現在位置をブックマーク追加（ライブのプレイヤー位置を使う）。
            Button {
                let time = player.currentTime().seconds
                BookmarksModel.shared.add(time.isFinite ? time : currentTime, for: item)
                scheduleAutoHide()
            } label: {
                Image(systemName: "bookmark").font(.title3)
            }
            // ブックマーク一覧
            Button {
                showingBookmarks = true
                hideTask?.cancel()
            } label: {
                Image(systemName: "list.bullet").font(.title3)
            }
            Button { toggleSilentPlayback() } label: {
                Image(systemName: playInSilentMode ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
            }
            // 再生速度（倍率）。タップでプリセットから選択。
            Menu {
                Picker("再生速度", selection: $playbackRate) {
                    ForEach(Self.speedOptions, id: \.self) { rate in
                        Text(Self.rateLabel(rate)).tag(rate)
                    }
                }
            } label: {
                Text(Self.rateLabel(playbackRate))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .onChange(of: playbackRate) { _, _ in
                applyPlaybackRate()
                scheduleAutoHide()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        // タイトル長押し中は全文を下に浮かせて表示（レイアウトは下げない）。
        .overlay(alignment: .bottomLeading) {
            if showingFullTitle {
                Text(item.title)
                    .font(.subheadline)
                    // 親（トップバー）の高さに収めようと省略されるのを防ぎ、必要な行数を確保する。
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.7))
                    .alignmentGuide(.bottom) { d in d[.top] }
            }
        }
    }

    private var centerControls: some View {
        HStack(spacing: 20) {
            Button { goPrev() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 28))
                    .frame(width: 56, height: 56).contentShape(Rectangle())
            }
            .disabled(index <= 0)
            Button { skip(-Double(skipSeconds)) } label: {
                Image(systemName: "gobackward.\(skipSeconds)")
                    .frame(width: 56, height: 56).contentShape(Rectangle())
            }
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 64, height: 56).contentShape(Rectangle())
            }
            Button { skip(Double(skipSeconds)) } label: {
                Image(systemName: "goforward.\(skipSeconds)")
                    .frame(width: 56, height: 56).contentShape(Rectangle())
            }
            Button { goNext() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 28))
                    .frame(width: 56, height: 56).contentShape(Rectangle())
            }
            .disabled(index >= items.count - 1)
        }
        .font(.system(size: 40))
    }

    private func goPrev() {
        guard index > 0 else { return }
        index -= 1
    }

    private func goNext() {
        guard index < items.count - 1 else { return }
        index += 1
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text(Self.timeString(currentTime, padHours: duration >= 3600))
                .font(.caption.monospacedDigit())
            // 現在位置より前のブックマークへ（無ければ先頭へ）。
            Button { goToPreviousBookmark() } label: {
                Image(systemName: "backward.frame.fill")
            }
            .font(.title3)
            .tint(.yellow)
            CircularSeekBar(value: $currentTime, duration: duration,
                            bookmarks: BookmarksModel.shared.bookmarks(for: item)) { editing in
                isScrubbing = editing
                if editing {
                    hideTask?.cancel()
                    beginScrub()
                } else {
                    seeker.seek(toSeconds: currentTime, tolerance: 0)   // 最終位置へ正確にシーク
                    endScrub()
                    scheduleAutoHide()
                }
            }
            // 現在位置より後のブックマークへ（無ければ何もしない）。
            Button { goToNextBookmark() } label: {
                Image(systemName: "forward.frame.fill")
            }
            .font(.title3)
            .tint(.yellow)
            Text(Self.timeString(duration, padHours: duration >= 3600))
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    /// 現在位置より前のブックマークへ移動。2秒以内に直前のブックマークがある場合は
    /// 「通過したばかり」とみなしてさらに一つ前へ。前が無ければ先頭(0)へ戻る。
    private func goToPreviousBookmark() {
        let marks = BookmarksModel.shared.bookmarks(for: item)
        let preceding = marks.filter { $0 <= currentTime + 0.001 }   // 現在位置以前
        guard let nearest = preceding.last else {
            seekTo(0)
            return
        }
        if currentTime - nearest <= 2.0 {
            seekTo(preceding.dropLast().last ?? 0)
        } else {
            seekTo(nearest)
        }
    }

    /// 現在位置より後の最初のブックマークへ移動。無ければ何もしない。
    private func goToNextBookmark() {
        let marks = BookmarksModel.shared.bookmarks(for: item)
        guard let next = marks.first(where: { $0 > currentTime + 0.001 }) else { return }
        seekTo(next)
    }

    private func seekTo(_ time: Double) {
        currentTime = time
        seeker.seek(toSeconds: time, tolerance: 0)
        scheduleAutoHide()
    }

    // MARK: 再生制御

    private func setUp() {
        seeker.setPlayer(player)
        guard PlaybackModel.shared.load(item: item, playInSilentMode: playInSilentMode) else {
            hasSource = false
            return
        }
        hasSource = true
        isPlaying = true
        // シーク中だけ有効化する待機設定が前アイテムから残らないよう、即時再生モードへ戻す。
        restoreStallWaitingWhenPlaying = false
        player.automaticallyWaitsToMinimizeStalling = false
        applyPlaybackRate()
        scheduleAutoHide()
    }

    /// 現在の再生速度をプレイヤーへ反映する。再生中なら即時、停止中は次回 play() に反映。
    private func applyPlaybackRate() {
        let rate = Float(playbackRate)
        player.defaultRate = rate
        if player.timeControlStatus != .paused {
            player.rate = rate
        }
    }

    /// 速度ラベル（例: 1x / 1.5x / 0.75x）。
    private static func rateLabel(_ rate: Double) -> String {
        "\(String(format: "%g", rate))x"
    }

    private func tick() {
        if !isScrubbing {
            let t = player.currentTime().seconds
            if t.isFinite { currentTime = t }
        }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            duration = d
        }
        isPlaying = player.timeControlStatus == .playing
        // 再生待ち（バッファ読み込み中）はコントロールを隠してスピナーを出す。
        isWaiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        // シーク後、再生が実際に再開して安定したら、元の即時再生モードへ戻す。
        if restoreStallWaitingWhenPlaying, player.timeControlStatus == .playing {
            player.automaticallyWaitsToMinimizeStalling = false
            restoreStallWaitingWhenPlaying = false
        }
    }

    private func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            hideTask?.cancel()       // 停止中はコントロールを出したままにする
        } else {
            player.play()
            isPlaying = true
            scheduleAutoHide()
        }
    }

    /// 再生中なら一時停止する（シート/解析を開く前に呼ぶ）。
    private func pausePlayback() {
        guard player.timeControlStatus != .paused else { return }
        player.pause()
        isPlaying = false
        hideTask?.cancel()
    }

    private func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// シーク（スクラブ）開始: その位置の音を出すため再生状態にする。
    private func beginScrub() {
        guard !scrubAudioActive else { return }
        scrubAudioActive = true
        wasPlayingBeforeScrub = (player.timeControlStatus == .playing)
        // ストリーミングではシーク先のバッファが空なので、待たない設定（即時再生）のままだと
        // シーク後に止まったまま自動再開しない。シーク中だけ「再生可能になるまで待つ」を許可する。
        restoreStallWaitingWhenPlaying = false
        player.automaticallyWaitsToMinimizeStalling = true
        player.play()
        isPlaying = true
    }

    /// シーク終了: 元の再生/停止状態へ戻す。
    private func endScrub() {
        guard scrubAudioActive else { return }
        scrubAudioActive = false
        if !wasPlayingBeforeScrub {
            player.pause()
            isPlaying = false
            // 停止確定なら即、元の即時再生モードへ戻す。
            player.automaticallyWaitsToMinimizeStalling = false
        } else {
            // 再生継続。シーク先のバッファが溜まり再生が安定したら（tick で）即時再生モードへ戻す。
            restoreStallWaitingWhenPlaying = true
        }
    }

    /// プレイヤー上のドラッグ（GestureSurface のパンから呼ばれる）。
    /// - 横方向: シーク。上半分=60秒・下半分=30秒を単位に移動（コントロール表示中も可）。
    /// - 縦方向: 回転。縦状態で上スワイプ→横、横状態で下スワイプ→縦（YouTube ライク）。
    private func handlePanChanged(translation: CGSize, startLocation: CGPoint, viewSize: CGSize) {
        guard hasSource, duration > 0 else { return }
        // 横方向が主のドラッグだけシークプレビューを出す（コントロール表示中も可）。
        guard abs(translation.width) > abs(translation.height) else { return }
        if dragStartTime == nil {
            dragStartTime = currentTime
            dragUnit = Double(startLocation.y < viewSize.height / 2 ? seekUnitTop : seekUnitBottom)
            isScrubbing = true   // tick による currentTime 上書きを止める
            beginScrub()   // シーク中も音を出す
        }
        let start = dragStartTime ?? currentTime
        let units = (translation.width / pointsPerUnit).rounded(.towardZero)
        let target = min(max(0, start + units * dragUnit), duration)
        pendingSeekTarget = target
        currentTime = target   // コントローラのシークバーを目標位置へ追従
        // 指を離す前から動画を追従させる（どのシーンか分かるように）。
        seeker.seek(toSeconds: target, tolerance: 0.5)
    }

    private func handlePanEnded(translation: CGSize) {
        let isHorizontal = abs(translation.width) > abs(translation.height)
        let target = pendingSeekTarget
        dragStartTime = nil
        pendingSeekTarget = nil
        endScrub()   // 元の再生/停止状態へ戻す
        isScrubbing = false

        if isHorizontal {
            guard let target else { return }
            seeker.seek(toSeconds: target, tolerance: 0)   // 最終位置へ正確にシーク
            currentTime = target
            if controlsVisible { scheduleAutoHide() }      // 操作中は自動非表示を延長
        } else {
            // 縦スワイプ
            guard abs(translation.height) > rotateThreshold else { return }
            if translation.height < 0 {
                // 上スワイプ → 横（縦状態のときのみ）
                if !OrientationManager.shared.isLandscape {
                    OrientationManager.shared.force(.landscapeRight)
                }
            } else {
                // 下スワイプ
                if OrientationManager.shared.isLandscape {
                    OrientationManager.shared.force(.portrait)   // 横（フルスクリーン）→ 縦
                } else {
                    pip.start()                                   // 縦（非フルスクリーン）→ PiP
                }
            }
        }
    }

    /// シングルタップ＝コントロール表示切替。
    private func handleSingleTap() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleAutoHide() }
    }

    /// ダブルタップ＝左=戻る/右=進む。
    private func handleDoubleTap(forward: Bool) {
        skip(forward ? Double(doubleTapSeconds) : -Double(doubleTapSeconds))
        doubleTapHint = (forward, doubleTapSeconds)
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(0.6))
            if !Task.isCancelled { doubleTapHint = nil }
        }
    }

    private func skip(_ delta: Double) {
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, currentTime + delta))
        currentTime = target
        seek(to: target)
        scheduleAutoHide()
    }

    private func engageFastForward() {
        guard !fastForwarding, hasSource else { return }
        fastForwarding = true
        player.rate = 4.0
    }

    private func disengageFastForward() {
        guard fastForwarding else { return }
        fastForwarding = false
        player.rate = Float(playbackRate)   // 通常速度で再生継続（スキップしない）
    }

    /// ブックマーク一覧の小窓用。左右ダブルタップで指定秒数だけ移動する（メインと同じ操作）。
    private func miniTapZone(forward: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                skip(forward ? Double(doubleTapSeconds) : -Double(doubleTapSeconds))
            }
    }

    private func doubleTapHintLabel(_ hint: (forward: Bool, seconds: Int)) -> some View {
        VStack(spacing: 4) {
            Image(systemName: hint.forward ? "goforward" : "gobackward")
                .font(.system(size: 40))
            Text("\(hint.seconds)秒").font(.headline)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.5), in: Circle())
    }

    /// 一定時間操作が無ければコントロール（＝タイトルも）を隠す。停止中は隠さない。
    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard controlsVisible else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            // タイトル長押しで全文表示中は隠さない。
            if !Task.isCancelled, isPlaying, !isScrubbing, !showingFullTitle {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
            }
        }
    }

    /// サイレントモードでの再生可否を切り替える。
    private func toggleSilentPlayback() {
        playInSilentMode.toggle()
        AudioSessionManager.configure(playInSilentMode: playInSilentMode)
        scheduleAutoHide()
    }

    /// 時間文字列。`padHours` が true なら 1 時間未満でも `h:mm:ss` 形式にして桁を固定する
    /// （総時間が 1 時間超のとき現在時間の桁ぶれでシークバーの幅が変わるのを防ぐ）。
    static func timeString(_ seconds: Double, padHours: Bool = false) -> String {
        guard seconds.isFinite, seconds >= 0 else { return padHours ? "0:00:00" : "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return (h > 0 || padHours)
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// 現在位置を**丸いサム**で示すシークバー（標準 `Slider` の幅広サムを置換）。
/// `Slider` 同様に `onEditingChanged` でスクラブの開始/終了を通知し、
/// ブックマーク位置（黄色）も重ねて表示する。タップ／ドラッグでシーク。
private struct CircularSeekBar: View {
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

/// 横スワイプシーク中に表示するシークバー（読み取り専用）。

/// AVPlayer を `AVPlayerLayer` で描画するビュー（コントロールは持たない）。
/// 画面遷移をまたいで PiP を継続させるため、永続的な `PlaybackModel` のレイヤービューを使う。
private struct PlayerLayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerUIView {
        PlaybackModel.shared.hostView()
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

/// プレイヤー中央のタッチ操作を UIKit の認識器でまとめて扱う透明レイヤー。
/// `UILongPressGestureRecognizer.numberOfTapsRequired = 1` が「ダブルタップして
/// 2 回目を離さず長押し」をそのまま表す。SwiftUI のジェスチャー合成では判定が
/// 安定しないため UIKit で実装し、`require(toFail:)` で各操作を明確に振り分ける。
private struct GestureSurface: UIViewRepresentable {
    var onSingleTap: () -> Void
    var onDoubleTap: (_ forward: Bool) -> Void
    var onFastForwardStart: () -> Void
    var onFastForwardEnd: () -> Void
    var onMenu: () -> Void
    var onPanChanged: (_ translation: CGSize, _ startLocation: CGPoint, _ viewSize: CGSize) -> Void
    var onPanEnded: (_ translation: CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let c = context.coordinator

        let single = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleSingle(_:)))
        single.numberOfTapsRequired = 1
        single.delegate = c

        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.handleDouble(_:)))
        double.numberOfTapsRequired = 2
        double.delegate = c

        // ダブルタップして 2 回目を離さず長押し → 2 倍速。
        let fast = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.handleFast(_:)))
        fast.numberOfTapsRequired = 1
        fast.minimumPressDuration = 0.25
        fast.delegate = c

        // 素の長押し → メニュー。
        let menu = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.handleMenu(_:)))
        menu.numberOfTapsRequired = 0
        menu.minimumPressDuration = 0.45
        menu.delegate = c

        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = c

        // 振り分け：シングルはダブル/長押しが不成立のときだけ。メニューはダブルタップ
        // 長押し（2倍速）やダブルタップ（スキップ）のときは出さない。
        single.require(toFail: double)
        single.require(toFail: fast)
        menu.require(toFail: fast)
        menu.require(toFail: double)

        [single, double, fast, menu, pan].forEach { view.addGestureRecognizer($0) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: GestureSurface
        private var panStart: CGPoint = .zero

        init(_ parent: GestureSurface) { self.parent = parent }

        @objc func handleSingle(_ g: UITapGestureRecognizer) { parent.onSingleTap() }

        @objc func handleDouble(_ g: UITapGestureRecognizer) {
            guard let view = g.view else { return }
            let x = g.location(in: view).x
            parent.onDoubleTap(x > view.bounds.width / 2)
        }

        @objc func handleFast(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began: parent.onFastForwardStart()
            case .ended, .cancelled, .failed: parent.onFastForwardEnd()
            default: break
            }
        }

        @objc func handleMenu(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { parent.onMenu() }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            let t = g.translation(in: view)
            let translation = CGSize(width: t.x, height: t.y)
            switch g.state {
            case .began:
                panStart = g.location(in: view)
            case .changed:
                parent.onPanChanged(translation, panStart, view.bounds.size)
            case .ended, .cancelled, .failed:
                parent.onPanEnded(translation)
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// 再生（AVPlayer・PiP・描画レイヤー）を画面遷移より長く保持する永続モデル。
/// これにより「PiP のままリストへ戻っても再生が続く」「別の動画を再生したら PiP を止める」を実現する。
@MainActor
@Observable
final class PlaybackModel {
    static let shared = PlaybackModel()

    let player = AVPlayer()
    let pip = PiPController()

    @ObservationIgnored private let host: PlayerUIView
    @ObservationIgnored private var loadedKey: String?

    private init() {
        host = PlayerUIView(player: player)
        // 十分なバッファまで待つと、帯域が動画ビットレートに足りないとき再生が始まらない
        // （バッファ済みでも待ち続ける）。待たず即再生し、不足時はスタールしつつ進める。
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = true
        pip.setup(with: host.playerLayer)
    }

    fileprivate func hostView() -> PlayerUIView { host }

    /// 指定アイテムを読み込み再生する。別アイテムなら PiP を止めてから差し替える。
    /// - Returns: 再生可能なリソースがあれば true。
    @discardableResult
    func load(item: MediaItem, playInSilentMode: Bool) -> Bool {
        guard let url = DownloadManager.shared.preferredURL(for: item) else { return false }
        AudioSessionManager.configure(playInSilentMode: playInSilentMode)
        // 同一アイテムが既にロード済みなら継続（PiP から戻った場合など）。
        if loadedKey == item.id, player.currentItem != nil {
            player.play()
            return true
        }
        if pip.isActive { pip.stop() }   // 別アイテム → 旧 PiP を停止
        // 数GB・長尺動画の省メモリ・高速ロード: 精密タイミングを取得せずに開く
        // （シークはキーフレーム単位になる）。先読みは AVPlayer の自動管理に任せてメモリを抑える。
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 0
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.replaceCurrentItem(with: playerItem)
        loadedKey = item.id
        player.play()
        return true
    }

    /// PiP 中でなければ一時停止する（一覧へ戻る時）。
    func pauseUnlessPiP() {
        guard !pip.isActive else { return }
        // PiP でないなら、抱えている AVPlayerItem（最大60秒バッファ＋ネットワークストリーム）を
        // 解放する。次に再生するとき load() で読み込み直す。
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedKey = nil
    }

    /// PiP 起動中なら停止する。
    func stopPiP() {
        if pip.isActive { pip.stop() }
    }
}

/// `AVPlayerLayer` を使った Picture in Picture の制御。
@MainActor
@Observable
final class PiPController: NSObject {
    /// この端末で PiP が使えるか。
    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// PiP が起動中か。
    var isActive = false

    /// PiP 開始直前（再生カテゴリへ切替）／終了後（設定へ戻す）に呼ぶフック。
    @ObservationIgnored var onWillStart: (() -> Void)?
    @ObservationIgnored var onDidStop: (() -> Void)?

    @ObservationIgnored private var controller: AVPictureInPictureController?

    func setup(with layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported(), controller == nil else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
    }

    func start() {
        guard let controller else { return }
        onWillStart?()
        // セッション切替直後は不可のことがあるため少し待ってから開始。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            controller.startPictureInPicture()
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }
}

extension PiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isActive = false
            self.onDidStop?()
        }
    }
}

private final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// スクラブ中に連続するシーク要求を「最新の目標位置を追いかける」形で滑らかに処理する。
/// 同時に走るシークは 1 つだけにし、新しい目標が来たら完了後に追従する。
@MainActor
final class SmoothSeeker {
    private weak var player: AVPlayer?
    private var isSeeking = false
    private var chaseTime: CMTime = .invalid
    private var chaseTolerance: CMTime = .zero

    func setPlayer(_ player: AVPlayer) { self.player = player }

    func seek(toSeconds seconds: Double, tolerance: Double) {
        chaseTime = CMTime(seconds: seconds, preferredTimescale: 600)
        chaseTolerance = CMTime(seconds: tolerance, preferredTimescale: 600)
        if !isSeeking { step() }
    }

    private func step() {
        guard let player, chaseTime.isValid else { isSeeking = false; return }
        isSeeking = true
        let target = chaseTime
        let tol = chaseTolerance
        player.seek(to: target, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            Task { @MainActor in self?.finished(target) }
        }
    }

    private func finished(_ target: CMTime) {
        if chaseTime == target {
            isSeeking = false
        } else {
            step()   // ドラッグ中に新しい目標が来ていれば追従
        }
    }
}

/// オーディオセッションのカテゴリを切り替える。
/// `.playback` はサイレントスイッチを無視して再生、`.ambient` はサイレント時にミュートされる。
enum AudioSessionManager {
    static func configure(playInSilentMode: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if playInSilentMode {
                try session.setCategory(.playback, mode: .moviePlayback)
            } else {
                try session.setCategory(.ambient)
            }
            try session.setActive(true)
        } catch {
            // 設定失敗時は既定の挙動にフォールバック。
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
