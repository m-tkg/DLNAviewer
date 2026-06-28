# CLAUDE.md

このリポジトリで作業する際の指針。詳細な機能仕様は `README.md` を参照。

## プロジェクト概要

ネットワーク上の DLNA/UPnP メディアサーバー（NAS 等）の**動画**を、iPhone / iPad / Mac 本体で
一覧・再生する **DMP（Digital Media Player）**。SwiftUI マルチプラットフォーム（iOS / iPadOS /
macOS **26 以降**）。個人利用・Xcode で自分のデバイスへ署名・配布する前提。bundle id は
`com.mtkg.dlnaviewer`。

## アーキテクチャ

2 層構成。

- **`DLNAKit/`** — プラットフォーム非依存のコア（ローカル SwiftPM パッケージ・ユニットテスト対象）
  - `SSDPDiscovery` — SSDP M-SEARCH によるサーバー探索（`NWConnectionGroup` マルチキャスト）
  - `DeviceDescriptionLoader` — デバイス記述 XML から ContentDirectory の controlURL 抽出
  - `ContentDirectoryClient` — SOAP `Browse`(BrowseDirectChildren) の発行
  - `DIDLParser` — DIDL-Lite XML → `MediaContainer` / `MediaItem`
  - 永続化ストア群（UserDefaults に JSON）: `ManualServerStore` / `RatingStore` / `BookmarkStore` /
    `TagStore` / `ThumbnailOverrideStore` / `FavoriteFolderStore`
  - `Models` — `MediaServer` / `MediaContainer` / `MediaItem` / `MediaResource`。
    `MediaItem.persistentKey`（後述）/ `Update`（`ReleaseInfo` / `VersionComparator`）
- **`App/`** — SwiftUI アプリ（iOS / macOS 共通ソース）
  - 画面: `ServerListView`（ルート）/ `BrowseView`（一覧。`downloadsMode` でダウンロード一覧も兼ねる）/
    `PlayerView`（iOS カスタムプレイヤー）/ `DownloadsView` / `SettingsView` / `TagEditorView` 他
  - `@Observable` モデル: `LibraryModel` / `RatingsModel` / `BookmarksModel` / `TagsModel` /
    `ThumbnailsModel` / `FavoritesModel` / `DownloadManager`（多くは `shared` シングルトン）
  - 解析系（iOS）: `SceneDescriber`（シーン説明）/ `TagSuggester`（タグ提案）/ `ChapterDetector`（自動チャプター）
  - 同期: `CloudSync`（UserDefaults を NSUbiquitousKeyValueStore にミラー）
  - アップデート（macOS のみ・`MacUpdater.swift`）: `UpdateService`（GitHub Release 取得・zip DL）/
    `SelfUpdater`（ditto 展開・`.app` 入れ替え・再起動）/ `UpdateChecker`（設定画面の状態管理）
- **`project.yml`** — [xcodegen](https://github.com/yonaskolb/XcodeGen) のプロジェクト定義

`DLNAviewer.xcodeproj` は xcodegen の生成物で **gitignore 対象（コミットしない）**。手で編集せず、
`project.yml` を変更して `xcodegen generate` で再生成する。

## ビルド / テスト

`App/` 配下のファイルを**追加・削除・リネームしたら必ず `xcodegen generate`** してからビルドする。

```sh
# プロジェクト再生成（App/ のファイル増減後に必須）
xcodegen generate

# ビルド（両プラットフォームで確認する）
xcodebuild -project DLNAviewer.xcodeproj -scheme DLNAviewer -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DLNAviewer.xcodeproj -scheme DLNAviewer -destination 'generic/platform=iOS' -allowProvisioningUpdates build

# DLNAKit のユニットテスト（swift-testing）
cd DLNAKit && swift test
```

- **SourceKit が出す `No such module 'DLNAKit'` はノイズ**。`xcodebuild` は通る。判断はビルド結果で行う。
- 変更後は **iOS と macOS の両方**をビルドして確認する。

## 配布 / CI

- **iOS / iPadOS — Xcode Cloud → TestFlight**。
  - ワークフローの **scheme は必ず `DLNAviewer`**。`DLNAKit`（ライブラリ）を選ぶとアプリではなく
    パッケージをアーカイブし、全エクスポートが `exit 70` で失敗する（`DLNAKit` がアルファベット順で
    先頭のため自動選択で誤りやすい）。
  - `.xcodeproj` は未コミットなので、`ci_scripts/ci_post_clone.sh` がクローン後に `xcodegen generate`
    する（これが無いと Xcode Cloud がプロジェクトを見つけられない）。
- **macOS — GitHub Actions（`.github/workflows/macos-release.yml`）→ GitHub Release**。
  - `project.yml` の `MARKETING_VERSION` をそのままタグ化する（`v<MARKETING_VERSION>`。
    例: `1.0.1` → `v1.0.1`）。既存リリースがあればスキップ（＝バージョンを上げた push のみリリース）。
  - 未署名ビルド後に自前 `codesign`。署名/公証シークレット未設定なら ad-hoc にフォールバック。
- 両 CI とも **ドキュメントのみ（`*.md` 等）の変更ではビルドしない**（GitHub Actions は `paths-ignore`、
  Xcode Cloud は Start Condition の Files and Folders で `App` / `DLNAKit` / `project.yml` / `ci_scripts` を指定）。
- 新ビルド配布時は **`CURRENT_PROJECT_VERSION`（必要なら `MARKETING_VERSION`）を上げる**。同一バージョン/
  ビルド番号は App Store Connect に弾かれる。
- CI runner は **Swift 6.2 を持つ Xcode** が必要（`DLNAKit` は `swift-tools-version: 6.2`・`.v26` 使用）。
  GitHub Actions は `setup-xcode` で `latest-stable` にピン留め。Xcode Cloud は新しめの Xcode を選ぶ。

### バージョンを上げる

バージョンは `project.yml` の 2 つの値で管理する（`MARKETING_VERSION` = 表示版・タグ採番用、
`CURRENT_PROJECT_VERSION` = ビルド番号）。

1. **ビルド番号を +1**: `CURRENT_PROJECT_VERSION` を上げる（新ビルド配布のたびに必須。同一だと
   App Store Connect に弾かれる）。
2. **表示バージョンを変える場合**は `MARKETING_VERSION` も更新（例: `1.0` → `1.0.1`）。
3. `main` へマージすると、**macOS** は `v<MARKETING_VERSION>`（例 `v1.0.1`）で GitHub Release を
   自動作成、**iOS** は Xcode Cloud がビルドして TestFlight へ配信。
4. ただし `MARKETING_VERSION` を据え置くと、macOS は**既存タグと衝突してリリースをスキップ**する
   （＝表示バージョンを上げた push のみ macOS Release が出る）。TestFlight は別管理なので
   ビルド番号さえ上げれば配信される。

## 署名 / エンタイトルメント / アイコン（配布でハマりやすい点）

- **エンタイトルメントはプラットフォーム別**（`project.yml` で `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` 出し分け）。
  - `App/DLNAviewer-iOS.entitlements` — iCloud KVS のみ。
  - `App/DLNAviewer-macOS.entitlements` — App Sandbox 無効 + iCloud KVS。
  - 共有して macOS 専用キー `com.apple.security.app-sandbox` を iOS に混ぜると **App Store 署名が失敗**する。
- **App アイコンはアルファチャンネル/透過 不可**（App Store 検証で `Invalid large app icon` になる）。
  `App/Assets.xcassets/AppIcon.appiconset/*.png` は不透明（背景塗りつぶし）にする。
- 輸出コンプライアンスは `Info.plist` の `ITSAppUsesNonExemptEncryption=false`（標準 TLS のみ＝免除対象）を
  宣言済み。アップロードごとの質問は出ない。
- App ID には **iCloud capability** を有効化しておく（KVS のため。未設定だと managed 署名が失敗）。
  multicast は承認制で現状コメントアウト。

## コーディング規約 / 慣習

- 最低 OS は **26 以降**。後方互換は考えず最新 API（`@Observable`、最新 SwiftUI、`VideoPlayer`、
  FoundationModels 等）を積極活用してよい。
- プラットフォーム差分は `#if os(iOS)` / `#if canImport(UIKit)` / `#if canImport(FoundationModels)` で分岐。
  Vision/AVFoundation を使う解析系は iOS 中心。
- **iOS 27 / macOS 27 SDK 専用 API**（例: FoundationModels の `Attachment`）は
  `#if canImport(FoundationModels, _version: 2.0)` で **compile-time に分岐**する。`@available` は実行時
  ガードに過ぎず、古い SDK（CI の安定版 Xcode 等）ではコンパイル時にシンボルが無く失敗するため。
- 永続化ストアは「**エンコード失敗時に既存データを消さない**」方針。`KeyValueStorage` プロトコルで
  テスト時にインメモリ差し替え可能。
- **動画ごとの永続データ（評価・ブックマーク・タグ・サムネ上書き・生成サムネキャッシュ）のキーは
  `MediaItem.persistentKey`**（= タイトル＋`res@duration`(秒)＋`res@size` の合成。尺/サイズが無ければ
  タイトルのみに自然劣化）。サーバーの object id 変更に強い。各モデルは `key(for:)` で旧スキーム
  （タイトルのみ／object id）から**一度だけ遅延移行**する。新しい永続データを足すときもこの方式に倣う。
  `id` 自体（`Identifiable`・ナビゲーション・プレイリスト）は変更しない。ダウンロード（実ファイル）は
  対象外で id ベースのまま。
- iCloud 同期対象キーを増やす場合は `CloudSync.syncKeys` に追加し、対応モデルの `reload()` を
  `ServerListView` の `.cloudSyncDidUpdate` ハンドラに追加する。
- Apple Intelligence 機能は `SystemLanguageModel` の availability を確認し、緩和ガードレール
  `.permissiveContentTransformations` を用いる。利用不可時は理由を UI に出す。

## 開発の進め方（ユーザー指針）

- **実装前に設計を提案する**: 複数案のメリット/デメリットを併記し、シンプルでメンテしやすい 1 案を
  選定。採用案が将来どう破綻し得るかも添える。
- **TDD**（t-wada 流）: 先にテスト → 失敗確認 → コミット → 実装で緑。`DLNAKit` のストア類は
  `DLNAKit/Tests/DLNAKitTests/` にテストを置く（`swift-testing` の `@Suite`/`@Test`）。
- 段階的に進め、エラーは解決してから次へ。指示にない機能を勝手に足さない。周囲の似た実装を参考にする。
- 一時ファイルはプロジェクト直下 `.claude/tmp` に置く。

## Git / PR

- `gh` を使う。`main` へ直接コミットせず作業ブランチを切る。
- エンタイトルメント（プラットフォーム別・macOS は App Sandbox 無効）と署名まわりは
  「署名 / エンタイトルメント / アイコン」を参照。

## 既知の制約

- 再生は `AVPlayer` 依存（H.264/HEVC の mp4/mov 等が中心。mkv 等は不可）。
- iOS の SSDP 自動探索には multicast エンタイトルメント（Apple 承認）が必要。承認前でも手動登録で全機能可。
- macOS は App Sandbox 無効化のため iCloud KVS 同期が効かないことがある。
