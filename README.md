# DLNAviewer

ネットワーク上の DLNA/UPnP メディアサーバー（NAS 等）の**動画**を、iPhone / iPad / Mac
本体で一覧・再生する **DMP（Digital Media Player）** アプリです。

- 役割: DMP（端末本体で再生。外部レンダラー操作 DMC は非対応）
- メディア: 動画
- プラットフォーム: iOS / iPadOS / macOS **26 以降**（SwiftUI マルチプラットフォーム）
- bundle id: `com.mtkg.dlnaviewer`

## 主な機能

### サーバー / 一覧
- DLNA サーバーの**自動探索（SSDP/UPnP）** と **手動登録**（記述 URL）
- フォルダ階層のブラウズ、**リスト / アイコン（グリッド）表示**切替
- **サムネイル**表示（サーバー提供のサムネ優先、無ければ動画から生成。縦長動画も崩れず全体表示。サイズ3段階）
- **検索**（一覧最上部で下スワイプ → 検索バー。**正規表現対応**、無効時は部分一致）
- **評価フィルタ**（like / dislike / 評価なし。フォルダは常に表示）
- フォルダ内容の**メモリキャッシュ**、下スワイプで**再読み込み**
- トップに **「ダウンロード済み」** 項目（オフライン視聴一覧）

### 再生（iOS カスタムプレイヤー）
- タップでコントロール表示、その間だけタイトル表示。一定時間で自動非表示
- **先読みバッファ**でシーク・早送りを安定化、シーク中は映像がライブ追従
- コントロール非表示中の**横スワイプでシーク**（画面の上半分/下半分で秒数単位、**設定で変更可**）。シーク中はシークバー表示
- **縦スワイプで操作**: 縦→上で横（フルスクリーン）、横→下で縦、縦→下で **PiP**
- **ピクチャインピクチャ**（バックグラウンド再生、PiP のまま一覧へ戻っても継続、別動画再生で旧 PiP 停止、前面復帰で自動解除）
- **サイレントモードでも再生**できるトグル
- **評価**（like / dislike / なし）— 長押し / スワイプ
- **ダウンロード**（端末ローカル保存・オフライン再生）— 長押しメニュー。済はチェックマーク、サイズ表示、削除。ダウンロード中はサムネ下にプログレスバー
- **ブックマーク**（複数の再生位置を記録）— シークバーにマーカー、一覧ボタンで**シーンのサムネ付き一覧**（タップでジャンプ / スワイプで削除）。一覧表示中は画面下にミニプレイヤー

### macOS
- 標準 `VideoPlayer`（PiP も標準対応）。一覧/検索/フィルタ/ダウンロード/評価は共通

## 構成

| パス | 役割 |
|------|------|
| `DLNAKit/` | プラットフォーム非依存のコア（SwiftPM パッケージ・ユニットテスト対象） |
| `App/` | SwiftUI アプリ（iOS / macOS 共通ソース） |
| `project.yml` | [xcodegen](https://github.com/yonaskolb/XcodeGen) 用のプロジェクト定義 |

### DLNAKit の主なコンポーネント
- `SSDPDiscovery` — SSDP M-SEARCH によるサーバー自動探索（`NWConnectionGroup` マルチキャスト）
- `DeviceDescriptionLoader` — デバイス記述 XML から ContentDirectory の controlURL を抽出
- `ContentDirectoryClient` — SOAP `Browse`(BrowseDirectChildren) の発行
- `DIDLParser` — DIDL-Lite XML を `MediaContainer` / `MediaItem` に変換（サムネ/duration 等）
- `ManualServerStore` / `RatingStore` / `BookmarkStore` — 手動サーバー・評価・ブックマークの永続化

## ビルド

事前に [xcodegen](https://github.com/yonaskolb/XcodeGen) が必要です（`brew install xcodegen`）。

```sh
# Xcode プロジェクトを生成
xcodegen generate

# Xcode で開く
open DLNAviewer.xcodeproj
```

コマンドラインからのビルド例:

```sh
# macOS
xcodebuild -project DLNAviewer.xcodeproj -scheme DLNAviewer -destination 'platform=macOS' build

# iOS シミュレータ
xcodebuild -project DLNAviewer.xcodeproj -scheme DLNAviewer \
  -destination 'generic/platform=iOS Simulator' build
```

実機へインストールする場合は、Xcode の Signing & Capabilities で自分の Apple ID チーム
を設定してください。

## テスト

```sh
cd DLNAKit && swift test
```

## 自動探索（SSDP / UPnP）について

DLNA サーバーは SSDP（`239.255.255.250:1900` へのマルチキャスト）で探索します。

### macOS
- **App Sandbox を無効化**しています（`App/DLNAviewer.entitlements`）。macOS のサンドボックス内
  ではマルチキャスト受信ができず（iOS のような multicast エンタイトルメントが macOS には無い）、
  自動探索が成立しないためです。個人利用・非 Mac App Store 配布が前提。
- 初回起動時に「ローカルネットワーク上のデバイスの検索」許可を求められたら **許可**してください。

### ターミナルからの探索確認（診断ツール）
```sh
cd DLNAKit && swift run ssdpprobe
```

### iOS で自動探索を有効にする
iOS 14+ では `com.apple.developer.networking.multicast` エンタイトルメントが必要で、**Apple の承認**を
要します（個人開発でも・無料）。承認前でも手動サーバー登録で全機能を利用できます。
1. [Multicast Networking Entitlement Request](https://developer.apple.com/contact/request/networking-multicast) から申請・承認
2. `App/DLNAviewer.entitlements` に `com.apple.developer.networking.multicast` を追加
3. `xcodegen generate` で再生成し署名

> 補足: ローカルネットワーク許可は bundle id 単位で管理され、`tccutil` のリセットが効かないことがあります。
> 許可状態が壊れた場合は再起動、または bundle id 変更で解消します。

## 既知の制約
- 再生は `AVPlayer` 依存のため、H.264/HEVC の mp4/mov 等が中心。mkv や非対応コーデックは再生できません
- ローカルサーバーは平文 HTTP のため、`Info.plist` で ATS（`NSAllowsArbitraryLoads`）を許可しています
