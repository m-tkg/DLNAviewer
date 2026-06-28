# DLNAviewer

ネットワーク上の DLNA/UPnP メディアサーバー（NAS 等）の**動画**を、iPhone / iPad / Mac
本体で一覧・再生する **DMP（Digital Media Player）** アプリです。

- 役割: DMP（端末本体で再生。外部レンダラー操作 DMC は非対応）
- メディア: 動画
- プラットフォーム: iOS / iPadOS / macOS **26 以降**（SwiftUI マルチプラットフォーム）
- bundle id: `com.mtkg.dlnaviewer`

## 主な機能

### サーバー / 一覧
- DLNA サーバーの**自動探索（SSDP/UPnP）**（起動時は自動実行せず、再読み込み/「自動探索」ボタンで実行）と **手動登録**（記述 URL）
- フォルダ階層のブラウズ、**リスト / アイコン（グリッド）表示**切替（切替ボタンの**長押しで、表示中の一覧をクリップボードにコピー**）
- **サムネイル**表示（サーバー提供のサムネ優先、無ければ動画から生成。縦長動画も崩れず全体表示。サイズ3段階）
- **検索**（検索バーで動画名を検索。**正規表現対応**、無効時は部分一致）
- **タグ**（動画に任意のタグを付与。検索バーのタグ指定で絞り込み、タグの一括リネーム・削除）
- **ブックマークあり絞り込み**（検索バーのブックマークボタン）。ブックマークがある動画はサムネ左上にアイコン表示
- **評価フィルタ**（すべて / like / dislike / 評価なし の単一選択。フォルダは常に表示）
- **自動チャプター作成**（動画長押し）— 埋め込みチャプター、無ければシーン変化を検出して**ブックマークとして保存**。進捗・件数のリアルタイム表示、キャンセル可（後述）
- フォルダ内容の**メモリキャッシュ**、下スワイプで**再読み込み**
- トップは **登録済みサーバー → ネットワーク上で発見 → お気に入り（フォルダ長押しで登録）→ ダウンロード済み（オフライン視聴一覧）** の順に表示
- 「ダウンロード済み」一覧もファイルリストと**同じ操作**（検索・絞り込み・長押しメニュー・自動チャプター等）に対応

### 再生（iOS カスタムプレイヤー）
- タップでコントロール表示、その間だけタイトル表示。一定時間で自動非表示
- **先読みバッファ**でシーク・早送りを安定化、シーク中は映像がライブ追従
- **横スワイプでシーク**（コントロール表示中も可。画面の上半分/下半分で秒数単位、**設定で変更可**）。シーク中はコントロールと同じシークバー（丸インジケーター）を同じ位置に表示し、映像がライブ追従
- **ダブルタップでスキップ**（左=戻る / 右=進む。秒数は**設定で変更可**）
- **再生速度の変更**（コントロール上部のメニューからプリセット 0.5〜2.0倍。選択は端末に保持）
- **縦スワイプで操作**: 縦→上で横（フルスクリーン）、横→下で縦、縦→下で **PiP**
- **ピクチャインピクチャ**（バックグラウンド再生、PiP のまま一覧へ戻っても継続、別動画再生で旧 PiP 停止、前面復帰で自動解除）
- **サイレントモードでも再生**できるトグル
- **評価**（like / dislike / なし）— 長押し / スワイプ
- **ダウンロード**（端末ローカル保存・オフライン再生）— 長押しメニュー。済はチェックマーク、サイズ表示、削除。ダウンロード中はサムネ下にプログレスバー
- **ブックマーク**（複数の再生位置・チャプターを記録）— シークバーにマーカー、一覧ボタンで**シーンのサムネ付き一覧**（タップでジャンプ / スワイプで削除）。一覧表示中は画面下にミニプレイヤー（左右ダブルタップでスキップ）
- **ブックマークスキップ**（シークバー横のボタンで現在位置の前/後のブックマークへ移動。前へは無ければ先頭、直前2秒以内ならさらに一つ前へ。次へは無ければ何もしない）
- **タイトル長押し**で全文をその場に表示（省略表示の補完。表示中はコントロールが自動で消えない）
- 長押しメニューから **このシーンをサムネイルにする** / **タグを編集** / **このシーンを調べる**（後述）。メニューを開くと再生は一時停止

### シーン解析・AI（iOS / Apple Intelligence）
- **このシーンを調べる** — 再生中の長押しから現在フレームを解析
  - **Visual Look Up / Live Text**（被写体の調べる・画面内テキスト認識）
  - **シーンを説明（AI）** — オンデバイスの Foundation Models で日本語の具体的なシーン説明を生成（iOS 27+ は画像を直接モデルへ渡すマルチモーダル、iOS 26 は Vision 解析を橋渡し）
  - **画像で検索**（共有シート経由で Google レンズ等）
- **俳優を顔で調べる** — 現在フレームから Vision で顔を検出し、画像検索（Google レンズ等）で人物を調べる。複数人が写っている場合は顔のサムネ一覧から1人を選択（顔は周囲に余白を付けて切り出し）
- **AI でタグを提案** — タイトル / ファイル名 / フォルダ名などのメタデータから Foundation Models がタグを提案。「映像も解析して提案」で代表フレームの内容も加味（iOS 27+ は画像を直接モデルへ）
- ※ AI 機能は Apple Intelligence 対応端末・有効時のみ。利用不可時は理由を表示

### 自動チャプター（iOS）
- 一覧で動画を長押し →「自動チャプター作成」
- **埋め込みチャプター metadata** があれば採用、無ければ **Vision の特徴量**でシーン変化を検出
- 検出結果を**ブックマークとして保存**（プレイヤーの一覧にサムネ付きで並ぶ）
- 進捗バーと作成件数を**リアルタイム表示**、**キャンセル**可（中断時はその実行で作成したぶんを削除）
- 解析中は別アプリへ切り替えても約30秒は継続（バックグラウンドタスク）

### macOS
- 標準 `VideoPlayer`（PiP も標準対応）。一覧/検索/タグ/フィルタ/ダウンロード/評価/お気に入りは共通
- **アップデートチェック / 自動更新**（設定ダイアログ内）— GitHub Release の最新版を確認し、新しければその場でダウンロード・入れ替え・再起動

### 動画の同一性（評価・ブックマーク等の引き継ぎ）
- 評価・ブックマーク・タグ・サムネ上書き・生成サムネは、**タイトル＋再生時間＋ファイルサイズ**で動画を識別して保存
- サーバーの object id が再採番で変わっても、同じ動画なら設定を**引き継ぐ**（旧データは自動移行）
- サーバーが尺/サイズを提供しない場合はタイトルのみで判定。タイトル・尺・サイズがすべて一致する別ファイルは同一として扱われる

### 同期
- 設定・評価・ブックマーク・タグ・サムネ上書き・お気に入り・手動サーバーを **iCloud（Key-Value Store）** で端末間同期
- ※ macOS は App Sandbox 無効化のため iCloud KVS 同期が効かないことがあります

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
- `ManualServerStore` / `RatingStore` / `BookmarkStore` / `TagStore` / `ThumbnailOverrideStore` / `FavoriteFolderStore` — 手動サーバー・評価・ブックマーク・タグ・サムネ上書き・お気に入りフォルダの永続化

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

## 配布

- **iOS / iPadOS**: Xcode Cloud でビルドし **TestFlight** へ配信（ワークフローの scheme は `DLNAviewer`）。
- **macOS**: GitHub Actions（`.github/workflows/macos-release.yml`）で `main` への push 時にビルドし、
  `MARKETING_VERSION` から `v<MARKETING_VERSION>` タグ（例 `1.0.1` → `v1.0.1`）で **GitHub Release** を作成（バージョンを上げた時のみ）。
- どちらも**ドキュメント（`*.md` 等）だけの変更ではビルドしない**。
- 開発・CI・署名まわりの詳細な注意点は `CLAUDE.md` を参照。

## 自動探索（SSDP / UPnP）について

DLNA サーバーは SSDP（`239.255.255.250:1900` へのマルチキャスト）で探索します。

### macOS
- **App Sandbox を無効化**しています（`App/DLNAviewer-macOS.entitlements`）。macOS のサンドボックス内
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
2. `App/DLNAviewer-iOS.entitlements` に `com.apple.developer.networking.multicast` を追加
3. `xcodegen generate` で再生成し署名

> 補足: ローカルネットワーク許可は bundle id 単位で管理され、`tccutil` のリセットが効かないことがあります。
> 許可状態が壊れた場合は再起動、または bundle id 変更で解消します。

## 既知の制約
- 再生は `AVPlayer` 依存のため、H.264/HEVC の mp4/mov 等が中心。mkv や非対応コーデックは再生できません
- ローカルサーバーは平文 HTTP のため、`Info.plist` で ATS（`NSAllowsArbitraryLoads`）を許可しています
