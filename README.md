# FamlyRecorder

親子の日常会話の取りこぼしを防ぐ iOS アプリ。常時マイクをバッファリングし、会話を検知したら自動で録音・保存します。

## 機能

- **常時バッファ録音** — 最大 30 秒分の音声をリングバッファに保持。録音開始時に直前 15 秒を自動で取り込む
- **音声自動検出** — Apple SoundAnalysis フレームワークによる音声信頼度スコアを使用。話し声を検知したら自動録音開始、無音が続いたら自動停止
- **録音一覧 & 再生** — 日付・時間帯ごとにグループ化した一覧画面でその場で再生可能
- **バックグラウンド動作** — ホームボタンで裏に回った状態・画面ロック中も録音継続
- **手動録音** — 自動検知に加えてボタンでの手動開始/停止にも対応

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
├── ContentView           # 録音タブ（手動操作・状態表示）
│   └── RecorderManager   # 録音エンジン（@MainActor ObservableObject）
│       ├── AVAudioEngine / AVAudioSession
│       └── SpeechActivityDetector  # SoundAnalysis ラッパー
└── RecordingListView     # 一覧タブ（日付・時間帯グループ表示）
    ├── RecordingPlayer   # 再生コントローラ
    └── RecordingSupport  # データモデル・ファイル操作ユーティリティ
```

### 主要クラス

| クラス / 型 | 役割 |
|-------------|------|
| `RecorderManager` | 音声セッション管理、VAD 判定、録音ファイル書き出し |
| `SpeechActivityDetector` | `SNAudioStreamAnalyzer` で音声信頼度スコアを算出 |
| `TimedRingBuffer<T>` | 時間長付きリングバッファ（先頭トリムも対応） |
| `RecordingFileStore` | ファイル URL 生成・ディレクトリ管理・ファイル名パース |
| `RecordingPlayer` | `AVAudioPlayer` ベースの再生 + 進捗タイマー |

### 録音フロー

1. アプリ起動 → `prepare()` でマイク権限取得・エンジン起動
2. 入力タップから PCM バッファを受け取り、リングバッファに蓄積
3. `SpeechActivityDetector` が信頼度スコアを算出（フォアグラウンド: 毎バッファ / バックグラウンド: 4バッファに1回）
4. スコアが閾値（0.40）を超えて 0.35 秒持続 → `startClipRecording()`
5. 無音（スコア < 0.28）が 1.2 秒継続 → `stopClipRecording()`
6. 録音ファイルは `Documents/FamilyRecorder/recording-yyyyMMdd-HHmmss.wav` に保存

### バックグラウンド対応

- `UIBackgroundModes: audio` を Info.plist に設定済み
- `AVAudioSession` カテゴリは `playAndRecord + mixWithOthers` — バックグラウンド移行時にセッション設定を変更しない（`setPreferredIOBufferDuration` 呼び出しはエンジン停止を誘発するため除外）
- フォアグラウンド復帰時 (`UIScene.willEnterForegroundNotification`) に `AVAudioEngine` を完全再初期化
- 割り込み（電話着信等）終了後も無条件に完全再初期化

## テスト

```bash
xcodebuild -scheme FamlyRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

シミュレートモード (`RecorderManager(mode: .simulated)`) で録音エンジンの状態遷移・VAD ロジック・ファイル名パースをカバーする Unit Tests が含まれています。

## ライセンス

Private / Personal use
