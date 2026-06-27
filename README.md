# DLNAviewer

ネットワーク上の DLNA/UPnP メディアサーバー（NAS 等）の**動画**を、iPhone / iPad / Mac
本体で一覧・再生する **DMP（Digital Media Player）** アプリです。

- 役割: DMP（端末本体で AVPlayer 再生。外部レンダラー操作 DMC は非対応）
- メディア: 動画
- プラットフォーム: iOS / iPadOS / macOS **26 以降**（SwiftUI マルチプラットフォーム）

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
- `DIDLParser` — DIDL-Lite XML を `MediaContainer` / `MediaItem` に変換
- `ManualServerStore` — 手動登録サーバーの永続化

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

## 使い方

1. アプリを起動。
2. 右上の **＋** から DLNA サーバーのデバイス記述 URL（例: `http://192.168.1.10:8200/rootDesc.xml`）
   を手動登録する。または **自動探索**（アンテナアイコン）で同一 LAN を探索する。
3. サーバーをタップしてフォルダをドリルダウンし、動画を選ぶと AVPlayer で再生する。

## 自動探索（SSDP / UPnP）について

DLNA サーバーは SSDP（`239.255.255.250:1900` へのマルチキャスト）で探索します。

### macOS
- **App Sandbox を無効化**しています（`App/DLNAviewer.entitlements`）。macOS のサンドボックス内
  ではマルチキャスト受信ができず（iOS のような multicast エンタイトルメントが macOS には無い）、
  自動探索が成立しないためです。個人利用・非 Mac App Store 配布が前提。
- 初回起動時に「ローカルネットワーク上のデバイスの検索」許可を求められたら **許可**してください。
  拒否すると探索が無音で失敗します（システム設定 → プライバシーとセキュリティ → ローカル
  ネットワーク で後から ON に戻せます）。

### ターミナルからの探索確認（診断ツール）
アプリのサンドボックス/権限と切り分けて、ネットワーク上のサーバーを確認できます:

```sh
cd DLNAKit && swift run ssdpprobe
```

## iOS で自動探索（SSDP）を有効にする

iOS 14+ では `239.255.255.250:1900` へのマルチキャスト送受信に
`com.apple.developer.networking.multicast` エンタイトルメントが必要で、**Apple の承認**を
要します（個人開発でも）。承認前でも、上記の手動サーバー登録で全機能を利用できます。

承認後の手順:

1. [Multicast Networking Entitlement Request](https://developer.apple.com/contact/request/networking-multicast)
   から申請し、承認を受ける。
2. `App/DLNAviewer.entitlements` に以下を追加する。

   ```xml
   <key>com.apple.developer.networking.multicast</key>
   <true/>
   ```

3. `xcodegen generate` で再生成し、対応するプロビジョニングプロファイルで署名する。

macOS では App Sandbox を無効化することで探索が動作します（上記「macOS」参照）。

## 既知の制約

- 再生は `AVPlayer` 依存のため、H.264/HEVC の mp4/mov 等が中心。mkv や非対応コーデックは
  再生できません（一覧には複数 `<res>` があれば再生しやすい形式を優先選択）。広コーデック
  対応が必要な場合は将来 VLCKit 統合を検討。
- ローカルサーバーは平文 HTTP のため、`Info.plist` で ATS（`NSAllowsArbitraryLoads`）を許可
  しています。
