# FamlyRecorder v0.1

親子の日常会話の取りこぼしを防ぐ iOS アプリ。常時マイクをバッファリングし、会話を検知したら自動で録音・保存します。

## 機能

- **常時バッファ録音** — 最大 30 秒分の音声をリングバッファに保持。録音開始時に直前 15 秒を自動で取り込む
- **音声自動検出（VAD）** — フォアグラウンドは SoundAnalysis、バックグラウンド・スリープ中は RMS エネルギーベース検出に自動切替。話し声を検知したら自動録音開始、無音が続いたら自動停止
- **バックグラウンド・スリープ対応** — ホームボタンで裏に回った状態・画面ロック中も録音継続
- **手動録音** — ボタンでの手動開始/停止にも対応
- **録音一覧** — 日付・時間帯（1 時間単位）ごとにグループ化。時間帯はアコーディオンで折りたたみ可能。新規録音は自動でリストに反映
- **録音再生** — 専用プレイヤー画面で再生/停止・±15 秒スキップ・シーク操作

## 動作環境

| 項目 | 要件 |
|------|------|
| iOS | 17.0 以上 |
| Xcode | 16.0 以上 |
| Swift | 5.10 以上 |

## セットアップ

```bash
git clone https://github.com/kittakatakashi/FamlyRecorder.git
cd FamlyRecorder
open FamlyRecorder.xcodeproj
```

Xcode でスキームを `FamlyRecorder` に選択し、実機またはシミュレータでビルドします。

> **注意**: マイク録音は実機でのみ動作します。シミュレータではシミュレートモードで起動し、録音データは保存されません。

## アーキテクチャ

```
FamlyRecorderApp
├── ContentView              # 録音タブ（手動操作・状態表示）
│   └── RecorderManager      # 録音エンジン（@MainActor ObservableObject）
│       ├── AVAudioEngine / AVAudioSession
│       └── SpeechActivityDetector   # SoundAnalysis ラッパー（フォアグラウンド用）
├── RecordingListView        # 一覧タブ（日付・時間帯グループ・アコーディオン）
│   └── PlayerView           # 再生画面
│       └── RecordingPlayer  # AVAudioPlayer ベースの再生コントローラ
└── RecordingSupport         # データモデル・ファイル操作ユーティリティ
```

### 主要クラス

| クラス / 型 | 役割 |
|-------------|------|
| `RecorderManager` | 音声セッション管理、VAD 判定、録音ファイル書き出し |
| `SpeechActivityDetector` | `SNAudioStreamAnalyzer` で音声信頼度スコアを算出（フォアグラウンド） |
| `TimedRingBuffer<T>` | 時間長付きリングバッファ（先頭トリムも対応） |
| `RecordingFileStore` | ファイル URL 生成・ディレクトリ管理・ファイル名パース |
| `RecordingPlayer` | `AVAudioPlayer` ベースの再生 + 進捗タイマー |
| `PlayerView` | 再生専用画面（シーク・スキップ・時間表示） |

### 録音フロー

1. アプリ起動 → `prepare()` でマイク権限取得・エンジン起動
2. 入力タップから PCM バッファを受け取り、リングバッファに蓄積
3. VAD でスコアを算出
   - フォアグラウンド: `SpeechActivityDetector`（SoundAnalysis）
   - バックグラウンド: `energyBasedVADScore()`（`vDSP_rmsqv` による RMS 計算）
4. スコアが閾値（0.40）を超えて 0.35 秒持続 → `startClipRecording()`
5. 無音（スコア < 0.28）が 1.2 秒継続 → `stopClipRecording()`
6. 録音ファイルは `Documents/FamilyRecorder/recording-yyyyMMdd-HHmmss.wav` に保存

### バックグラウンド対応

- `UIBackgroundModes: audio` を Info.plist に設定済み
- `AVAudioSession` カテゴリは `.playAndRecord + .mixWithOthers`
- iOS の制約により `SNAudioStreamAnalyzer`（Core ML）はバックグラウンドで停止するため、バックグラウンド移行時は RMS エネルギーベース VAD に自動切替
- `UIScene.didEnterBackgroundNotification` でエンジン停止を検知して再起動
- フォアグラウンド復帰時 (`UIScene.willEnterForegroundNotification`) はエンジンが停止していた場合のみ再初期化（不要な再起動を回避）
- 割り込み（電話着信等）終了後は完全再初期化

### 再生とセッション共存

再生時は `AVAudioSession` のカテゴリを変更せず `overrideOutputAudioPort(.speaker)` でスピーカー出力に切替。録音セッション（`.playAndRecord`）を維持したまま再生するため、録音と再生を同時に行える。

## テスト

```bash
xcodebuild -scheme FamlyRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

シミュレートモード（`RecorderManager(mode: .simulated)`）で以下をカバーする Unit Tests（29 ケース）が含まれています。

| カテゴリ | ケース数 | 主な確認内容 |
|---------|---------|-------------|
| `TimedRingBuffer` | 6 | トリム・サフィックス取得・境界値 |
| `RecordingFileStore` | 5 | ファイル名生成・UTC パース・不正入力 |
| `RecorderManager` | 18 | 初期状態・手動録音・VAD 自動録音・エラー処理 |

## ライセンス

Private / Personal use
