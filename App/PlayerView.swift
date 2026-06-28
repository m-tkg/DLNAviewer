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
            let playerItem = AVPlayerItem(asset: AVURLAsset(url: url))
            playerItem.preferredForwardBufferDuration = 60
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            let player = AVPlayer(playerItem: playerItem)
            player.automaticallyWaitsToMinimizeStalling = true
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

    // 再生・PiP・描画レイヤーは永続モデルが保持する（画面遷移をまたいで継続）。
    private var player: AVPlayer { PlaybackModel.shared.player }
    private var pip: PiPController { PlaybackModel.shared.pip }

    @State private var hasSource = true
    @State private var controlsVisible = true
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var hideTask: Task<Void, Never>?
    @State private var showingBookmarks = false
    // シーク中の音声再生用
    @State private var scrubAudioActive = false
    @State private var wasPlayingBeforeScrub = false

    // スワイプシーク用
    @State private var viewHeight: CGFloat = 1
    // ダブルタップスキップのヒント表示
    @State private var doubleTapHint: (forward: Bool, seconds: Int)?
    @State private var hintTask: Task<Void, Never>?
    // 現在シーンの解析・画像検索
    @State private var analysisImage: CapturedImage?
    @State private var shareImage: CapturedImage?
    @State private var showingTagEditor = false
    @State private var dragStartTime: Double?
    @State private var dragUnit: Double = 60
    @State private var pendingSeekTarget: Double?
    @State private var seeker = SmoothSeeker()

    /// 縦スワイプで回転とみなす最小移動量。
    private let rotateThreshold: CGFloat = 60

    /// 横ドラッグ何ポイントで 1 単位進めるか。
    private let pointsPerUnit: CGFloat = 30

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

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
                if controlsVisible {
                    // 表示中はオーバーレイ内にタップ層を内蔵（バーが最前面で必ず反応）。
                    controlsOverlay.transition(.opacity)
                } else {
                    // 非表示中はタップ層のみ（シングル=表示・ダブル=左右スキップ）。
                    tapLayer.ignoresSafeArea()
                }
            } else {
                ContentUnavailableView(
                    "再生できません",
                    systemImage: "play.slash",
                    description: Text("このアイテムには再生可能なリソースがありません。")
                )
                .foregroundStyle(.white)
            }

            // スワイプシーク中はシークバーを表示
            if let target = pendingSeekTarget {
                SeekBarOverlay(current: target, duration: duration)
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
        .background {
            // 上半分／下半分の判定に使うビュー高さを取得。
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in viewHeight = h }
            }
        }
        // 左右スワイプでシーク（コントロール表示中も可。上半分=60秒/単位・下半分=30秒/単位）。
        .gesture(seekDrag)
        // 長押しで評価＋サムネイル設定＋シーン解析メニュー。
        .contextMenu {
            RatingMenu(item: item, ratings: ratings)
            Divider()
            Button {
                let time = player.currentTime().seconds
                if time.isFinite { ThumbnailsModel.shared.set(time, for: item) }
            } label: {
                Label("このシーンをサムネイルにする", systemImage: "photo")
            }
            Button {
                pausePlayback()
                showingTagEditor = true
            } label: {
                Label("タグを編集…", systemImage: "tag")
            }
            Divider()
            Button {
                pausePlayback()
                Task { if let image = await captureFrame() { analysisImage = CapturedImage(image: image) } }
            } label: {
                Label("このシーンを調べる", systemImage: "sparkles")
            }
            Button {
                pausePlayback()
                Task { if let image = await captureFrame() { shareImage = CapturedImage(image: image) } }
            } label: {
                Label("このシーンを画像検索…", systemImage: "magnifyingglass")
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
            Text(Self.timeString(currentTime)).font(.caption2.monospacedDigit()).foregroundStyle(.white)
            Slider(value: $currentTime, in: 0...max(duration, 0.1)) { editing in
                isScrubbing = editing
                if editing {
                    beginScrub()
                } else {
                    seeker.seek(toSeconds: currentTime, tolerance: 0)
                    endScrub()
                }
            }
            .overlay { bookmarkMarkers }
            Text(Self.timeString(duration)).font(.caption2.monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: コントロールオーバーレイ

    private var controlsOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)   // 装飾。タップは下の tapLayer / バーへ。

            // 空き領域のタップ層（グラデの上・バーの下）。シングル=表示切替、ダブル=スキップ。
            tapLayer.ignoresSafeArea()

            // バー（ボタン）は最前面。空き領域以外のタップは必ずボタンに届く。
            VStack(spacing: 0) {
                topBar
                tagBar
                Spacer()
                centerControls
                Spacer()
                bottomBar
            }
            .foregroundStyle(.white)
        }
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
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var centerControls: some View {
        HStack(spacing: 28) {
            Button { goPrev() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 28))
            }
            .disabled(index <= 0)
            Button { skip(-Double(skipSeconds)) } label: {
                Image(systemName: "gobackward.\(skipSeconds)")
            }
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 56)
            }
            Button { skip(Double(skipSeconds)) } label: {
                Image(systemName: "goforward.\(skipSeconds)")
            }
            Button { goNext() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 28))
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
            Text(Self.timeString(currentTime))
                .font(.caption.monospacedDigit())
            Slider(
                value: $currentTime,
                in: 0...max(duration, 0.1)
            ) { editing in
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
            .overlay { bookmarkMarkers }   // シークバー上にブックマーク位置を表示
            Text(Self.timeString(duration))
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private var bookmarkMarkers: some View {
        GeometryReader { geo in
            let marks = BookmarksModel.shared.bookmarks(for: item)
            let inset: CGFloat = 8
            let usable = max(geo.size.width - inset * 2, 1)
            ForEach(marks, id: \.self) { time in
                let frac = duration > 0 ? CGFloat(min(max(time / duration, 0), 1)) : 0
                Capsule()
                    .fill(.yellow)
                    .frame(width: 3, height: 12)
                    .position(x: inset + usable * frac, y: geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
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
        scheduleAutoHide()
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
        }
    }

    /// プレイヤー上のドラッグ。
    /// - 横方向: シーク。上半分=60秒・下半分=30秒を単位に移動（コントロール表示中も可）。
    /// - 縦方向: 回転。縦状態で上スワイプ→横、横状態で下スワイプ→縦（YouTube ライク）。
    private var seekDrag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                guard hasSource, duration > 0 else { return }
                // 横方向が主のドラッグだけシークプレビューを出す（コントロール表示中も可）。
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if dragStartTime == nil {
                    dragStartTime = currentTime
                    dragUnit = Double(value.startLocation.y < viewHeight / 2 ? seekUnitTop : seekUnitBottom)
                    beginScrub()   // シーク中も音を出す
                }
                let start = dragStartTime ?? currentTime
                let units = (value.translation.width / pointsPerUnit).rounded(.towardZero)
                let target = min(max(0, start + units * dragUnit), duration)
                pendingSeekTarget = target
                // 指を離す前から動画を追従させる（どのシーンか分かるように）。
                seeker.seek(toSeconds: target, tolerance: 0.5)
            }
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                let target = pendingSeekTarget
                dragStartTime = nil
                pendingSeekTarget = nil
                endScrub()   // 元の再生/停止状態へ戻す

                if isHorizontal {
                    guard let target else { return }
                    seeker.seek(toSeconds: target, tolerance: 0)   // 最終位置へ正確にシーク
                    currentTime = target
                    if controlsVisible { scheduleAutoHide() }      // 操作中は自動非表示を延長
                } else {
                    // 縦スワイプ
                    guard abs(value.translation.height) > rotateThreshold else { return }
                    if value.translation.height < 0 {
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
    }

    private func skip(_ delta: Double) {
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, currentTime + delta))
        currentTime = target
        seek(to: target)
        scheduleAutoHide()
    }

    /// コントロールの下に敷くタップ層（左右2分割）。
    /// シングルタップ＝コントロール表示切替、ダブルタップ＝左=戻る/右=進む。
    /// `onTapGesture` なのでボタン（上層）の操作を妨げない。
    /// コントロール表示中も、上層オーバーレイの背景はヒットテストを通すため空き領域で機能する。
    private var tapLayer: some View {
        HStack(spacing: 0) {
            tapZone(forward: false)
            tapZone(forward: true)
        }
    }

    private func tapZone(forward: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                skip(forward ? Double(doubleTapSeconds) : -Double(doubleTapSeconds))
                doubleTapHint = (forward, doubleTapSeconds)
                hintTask?.cancel()
                hintTask = Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    if !Task.isCancelled { doubleTapHint = nil }
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
                if controlsVisible { scheduleAutoHide() }
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
            if !Task.isCancelled, isPlaying, !isScrubbing {
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

    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

/// 横スワイプシーク中に表示するシークバー（読み取り専用）。
private struct SeekBarOverlay: View {
    let current: Double
    let duration: Double

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                GeometryReader { geo in
                    let frac = CGFloat(duration > 0 ? min(max(current / duration, 0), 1) : 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                        Capsule().fill(.white).frame(width: geo.size.width * frac, height: 4)
                        Circle().fill(.white)
                            .frame(width: 14, height: 14)
                            .offset(x: geo.size.width * frac - 7)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 16)
                HStack {
                    Text(iOSPlayer.timeString(current))
                    Spacer()
                    Text(iOSPlayer.timeString(duration))
                }
                .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

/// AVPlayer を `AVPlayerLayer` で描画するビュー（コントロールは持たない）。
/// 画面遷移をまたいで PiP を継続させるため、永続的な `PlaybackModel` のレイヤービューを使う。
private struct PlayerLayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerUIView {
        PlaybackModel.shared.hostView()
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
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
        player.automaticallyWaitsToMinimizeStalling = true
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
        let playerItem = AVPlayerItem(asset: AVURLAsset(url: url))
        playerItem.preferredForwardBufferDuration = 60
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.replaceCurrentItem(with: playerItem)
        loadedKey = item.id
        player.play()
        return true
    }

    /// PiP 中でなければ一時停止する（一覧へ戻る時）。
    func pauseUnlessPiP() {
        if !pip.isActive { player.pause() }
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
