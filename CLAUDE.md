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
  - `Models` — `MediaServer` / `MediaContainer` / `MediaItem` / `MediaResource`
- **`App/`** — SwiftUI アプリ（iOS / macOS 共通ソース）
  - 画面: `ServerListView`（ルート）/ `BrowseView`（一覧。`downloadsMode` でダウンロード一覧も兼ねる）/
    `PlayerView`（iOS カスタムプレイヤー）/ `DownloadsView` / `SettingsView` / `TagEditorView` 他
  - `@Observable` モデル: `LibraryModel` / `RatingsModel` / `BookmarksModel` / `TagsModel` /
    `ThumbnailsModel` / `FavoritesModel` / `DownloadManager`（多くは `shared` シングルトン）
  - 解析系（iOS）: `SceneDescriber`（シーン説明）/ `TagSuggester`（タグ提案）/ `ChapterDetector`（自動チャプター）
  - 同期: `CloudSync`（UserDefaults を NSUbiquitousKeyValueStore にミラー）
- **`project.yml`** — [xcodegen](https://github.com/yonaskolb/XcodeGen) のプロジェクト定義

`DLNAviewer.xcodeproj` は xcodegen の生成物（コミット対象だが手で編集しない）。

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

## コーディング規約 / 慣習

- 最低 OS は **26 以降**。後方互換は考えず最新 API（`@Observable`、最新 SwiftUI、`VideoPlayer`、
  FoundationModels 等）を積極活用してよい。
- プラットフォーム差分は `#if os(iOS)` / `#if canImport(UIKit)` / `#if canImport(FoundationModels)` で分岐。
  Vision/AVFoundation を使う解析系は iOS 中心。
- 永続化ストアは「**エンコード失敗時に既存データを消さない**」方針。`KeyValueStorage` プロトコルで
  テスト時にインメモリ差し替え可能。
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
- 個人利用前提のため `App/DLNAviewer.entitlements` は **App Sandbox 無効**（macOS の SSDP マルチキャスト用）。

## 既知の制約

- 再生は `AVPlayer` 依存（H.264/HEVC の mp4/mov 等が中心。mkv 等は不可）。
- iOS の SSDP 自動探索には multicast エンタイトルメント（Apple 承認）が必要。承認前でも手動登録で全機能可。
- macOS は App Sandbox 無効化のため iCloud KVS 同期が効かないことがある。
