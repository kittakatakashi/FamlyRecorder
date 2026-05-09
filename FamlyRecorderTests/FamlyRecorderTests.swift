//
//  FamlyRecorderTests.swift
//  FamlyRecorderTests
//
//  Created by kikuchitakashi on 2026/04/05.
//

import Foundation
import Testing
@testable import FamlyRecorder

struct FamlyRecorderTests {

    // MARK: - TimedRingBuffer

    @Test func timedRingBufferTrimsOldEntriesBeyondMaxDuration() {
        var buffer = TimedRingBuffer<String>()

        buffer.append("first", duration: 12, keepingMaxDuration: 30)
        buffer.append("second", duration: 10, keepingMaxDuration: 30)
        buffer.append("third", duration: 11, keepingMaxDuration: 30)

        #expect(buffer.entries.map(\.element) == ["second", "third"])
        #expect(buffer.totalDuration == 21)
    }

    @Test func timedRingBufferRemovesAllWhenSingleEntryExceedsMaxDuration() {
        var buffer = TimedRingBuffer<String>()

        buffer.append("oversize", duration: 35, keepingMaxDuration: 30)

        #expect(buffer.entries.isEmpty)
        #expect(buffer.totalDuration == 0)
    }

    @Test func timedRingBufferReturnsEmptyForNonPositiveTargetDuration() {
        var buffer = TimedRingBuffer<String>()
        buffer.append("a", duration: 5, keepingMaxDuration: 30)

        #expect(buffer.suffix(coveringLast: 0).isEmpty)
        #expect(buffer.suffix(coveringLast: -1).isEmpty)
    }

    @Test func timedRingBufferReturnsAllWhenTargetExceedsBufferedDuration() {
        var buffer = TimedRingBuffer<String>()
        buffer.append("a", duration: 5, keepingMaxDuration: 30)
        buffer.append("b", duration: 4, keepingMaxDuration: 30)

        let selection = buffer.suffix(coveringLast: 100)

        #expect(selection.map(\.element) == ["a", "b"])
        #expect(selection.map(\.trimLeadingDuration) == [0, 0])
    }

    @Test func timedRingBufferReturnsExactSuffixWithoutTrimming() {
        var buffer = TimedRingBuffer<String>()
        buffer.append("a", duration: 5, keepingMaxDuration: 30)
        buffer.append("b", duration: 4, keepingMaxDuration: 30)
        buffer.append("c", duration: 6, keepingMaxDuration: 30)

        let selection = buffer.suffix(coveringLast: 10)

        #expect(selection.map(\.element) == ["b", "c"])
        #expect(selection.map(\.trimLeadingDuration) == [0, 0])
    }

    @Test func timedRingBufferReturnsTrimmedLeadingChunkForPartialSuffix() {
        var buffer = TimedRingBuffer<String>()
        buffer.append("a", duration: 8, keepingMaxDuration: 30)
        buffer.append("b", duration: 7, keepingMaxDuration: 30)
        buffer.append("c", duration: 5, keepingMaxDuration: 30)

        let selection = buffer.suffix(coveringLast: 9)

        #expect(selection.map(\.element) == ["b", "c"])
        #expect(selection[0].trimLeadingDuration == 3)
        #expect(selection[1].trimLeadingDuration == 0)
    }

    // MARK: - RecordingFileStore

    @Test func recordingFileStoreBuildsStableM4aFileName() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let date = Date(timeIntervalSince1970: 0)

        let url = RecordingFileStore.outputURL(in: directory, date: date)

        #expect(url.path == "/tmp/recording-19700101-000000.m4a")
    }

    @Test func recordingFileStoreUsesM4aExtensionAndUtcTimestampFormat() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_712_345_678)

        let url = RecordingFileStore.outputURL(in: directory, date: date)

        #expect(url.pathExtension == "m4a")
        #expect(url.lastPathComponent.starts(with: "recording-"))
        #expect(url.lastPathComponent.contains("-"))
    }

    @Test func recordingFileDateParsesM4aFileName() {
        let date = RecordingFileStore.date(from: "recording-20260429-185430.m4a")
        #expect(date != nil)
    }

    @Test func recordingFileDateParsesWavFileNameForBackwardCompatibility() {
        let date = RecordingFileStore.date(from: "recording-20260429-185430.wav")
        #expect(date != nil)
    }

    @Test func digestDirectoryURLCreatesSubfolder() throws {
        let dir = try RecordingFileStore.digestDirectoryURL()
        #expect(dir.lastPathComponent == "Digest")
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func digestURLFormatsCorrectly() throws {
        let day = Date(timeIntervalSince1970: 0)  // 1970-01-01 UTC
        let url = try RecordingFileStore.digestURL(for: day)
        #expect(url.lastPathComponent == "digest-19700101.m4a")
    }

    // MARK: - RecordingFileStore.date(from:)

    @Test func recordingFileDateParsesStandardFileName() {
        let date = RecordingFileStore.date(from: "recording-20260429-185430.wav")
        #expect(date != nil)
        // UTC で 2026-04-29 18:54:30 であることを確認
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)
        #expect(comps.year == 2026)
        #expect(comps.month == 4)
        #expect(comps.day == 29)
        #expect(comps.hour == 18)
        #expect(comps.minute == 54)
        #expect(comps.second == 30)
    }

    @Test func recordingFileDateParsesSuffixedFileName() {
        let date = RecordingFileStore.date(from: "recording-20260429-185430-1.wav")
        #expect(date != nil)
    }

    @Test func recordingFileDateReturnsNilForInvalidFileName() {
        #expect(RecordingFileStore.date(from: "unknown.wav") == nil)
        #expect(RecordingFileStore.date(from: "recording-.wav") == nil)
        #expect(RecordingFileStore.date(from: "") == nil)
    }

    // MARK: - RecorderManager (simulated)

    @MainActor
    @Test func simulatedRecorderInitialStateIsSafeForIdleUi() {
        let recorder = RecorderManager(mode: .simulated)

        #expect(!recorder.permissionGranted)
        #expect(!recorder.isPrepared)
        #expect(!recorder.isBuffering)
        #expect(!recorder.isRecordingClip)
        #expect(recorder.bufferedSeconds == 0)
        #expect(!recorder.canControlRecording)
        #expect(recorder.lastSavedFileName == nil)
    }

    @MainActor
    @Test func simulatedRecorderPrepareEnablesBufferingAndControl() {
        let recorder = RecorderManager(mode: .simulated)

        recorder.prepare()

        #expect(recorder.permissionGranted)
        #expect(recorder.isPrepared)
        #expect(recorder.isBuffering)
        #expect(recorder.canControlRecording)
        #expect(recorder.bufferedSeconds == 5)
    }

    @MainActor
    @Test func simulatedRecorderPrepareIsIdempotent() {
        let recorder = RecorderManager(mode: .simulated)

        recorder.prepare()
        recorder.startClipRecording()
        recorder.stopClipRecording()

        let firstSaved = recorder.lastSavedFileName
        recorder.prepare()

        #expect(recorder.permissionGranted)
        #expect(recorder.isPrepared)
        #expect(recorder.isBuffering)
        #expect(recorder.bufferedSeconds == 5)
        #expect(recorder.lastSavedFileName == firstSaved)
    }

    @MainActor
    @Test func simulatedRecorderCannotStartBeforePrepare() {
        let recorder = RecorderManager(mode: .simulated)

        recorder.startClipRecording()

        #expect(!recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName == nil)
    }

    @MainActor
    @Test func simulatedRecorderStartAndStopUpdatesSavedFileState() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.startClipRecording()
        #expect(recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName == nil)

        recorder.stopClipRecording()

        #expect(!recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName?.hasSuffix(".m4a") == true)
    }

    @MainActor
    @Test func simulatedRecorderRepeatedStartDoesNotResetSession() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.startClipRecording()
        let isRecordingAfterFirstStart = recorder.isRecordingClip

        recorder.startClipRecording()

        #expect(isRecordingAfterFirstStart)
        #expect(recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName == nil)
    }

    @MainActor
    @Test func simulatedRecorderStopWithoutRecordingKeepsSavedFileNil() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.stopClipRecording()

        #expect(!recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName == nil)
    }


    @MainActor
    @Test func simulatedRecorderCanStartNewRecordingImmediatelyAfterStop() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.startClipRecording()
        recorder.stopClipRecording()
        let firstSavedFile = recorder.lastSavedFileName

        #expect(firstSavedFile?.hasSuffix(".m4a") == true)
        #expect(recorder.canControlRecording)
        #expect(!recorder.isRecordingClip)

        recorder.startClipRecording()

        #expect(recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName == nil)
        #expect(recorder.canControlRecording)
    }

    @MainActor
    @Test func simulatedRecorderStatusTextReflectsRecordingState() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        #expect(recorder.recordingStatusText.contains("待機中"))

        recorder.startClipRecording()
        #expect(recorder.recordingStatusText.contains("録音中"))
    }

    @MainActor
    @Test func simulatedRecorderStatusTextReflectsPermissionAndBufferState() {
        let recorder = RecorderManager(mode: .simulated)

        #expect(recorder.permissionStatusText.contains("マイク許可が必要"))
        #expect(recorder.bufferStatusText.contains("準備中"))

        recorder.prepare()

        #expect(recorder.permissionStatusText.contains("マイク許可済み"))
        #expect(recorder.bufferStatusText.contains("バッファ中"))
        #expect(recorder.bufferStatusText.contains("5"))
    }



    @MainActor
    @Test func simulatedRecorderStartsAutomaticallyWhenSpeechDetected() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.handleVoiceActivitySample(isSpeechDetected: true, timestamp: Date(timeIntervalSince1970: 100))
        recorder.handleVoiceActivitySample(isSpeechDetected: true, timestamp: Date(timeIntervalSince1970: 100.5))

        #expect(recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName == nil)
    }

    @MainActor
    @Test func simulatedRecorderStopsAutomaticallyAfterSilenceWindow() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        recorder.startClipRecording()
        #expect(recorder.isRecordingClip)

        recorder.handleVoiceActivitySample(isSpeechDetected: true, timestamp: Date(timeIntervalSince1970: 200))
        recorder.handleVoiceActivitySample(isSpeechDetected: true, timestamp: Date(timeIntervalSince1970: 200.5))

        recorder.handleVoiceActivitySample(isSpeechDetected: false, timestamp: Date(timeIntervalSince1970: 201.0))
        recorder.handleVoiceActivitySample(isSpeechDetected: false, timestamp: Date(timeIntervalSince1970: 206.1))

        #expect(!recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName?.hasSuffix(".m4a") == true)
    }

    @MainActor
    @Test func simulatedRecorderKeepsRecordingWhileSpeechContinues() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        recorder.startClipRecording()

        recorder.handleVoiceActivitySample(isSpeechDetected: true, timestamp: Date(timeIntervalSince1970: 300))
        recorder.handleVoiceActivitySample(isSpeechDetected: true, timestamp: Date(timeIntervalSince1970: 300.5))
        recorder.handleVoiceActivitySample(isSpeechDetected: false, timestamp: Date(timeIntervalSince1970: 301.0))
        recorder.handleVoiceActivitySample(isSpeechDetected: true, timestamp: Date(timeIntervalSince1970: 301.1))
        recorder.handleVoiceActivitySample(isSpeechDetected: false, timestamp: Date(timeIntervalSince1970: 301.9))

        #expect(recorder.isRecordingClip)
    }


    @MainActor
    @Test func simulatedRecorderIgnoresShortNoiseBursts() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 400))
        recorder.handleVoiceActivityScore(0.4, timestamp: Date(timeIntervalSince1970: 400.1))
        recorder.handleVoiceActivityScore(0.2, timestamp: Date(timeIntervalSince1970: 400.2))

        #expect(!recorder.isRecordingClip)
    }

    @MainActor
    @Test func simulatedRecorderAutoStartsAfterSustainedSpeech() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 500.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 500.2))
        #expect(!recorder.isRecordingClip)  // 0.2秒 < 0.35秒なのでまだ未開始

        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 500.4))

        #expect(recorder.isRecordingClip)   // 0.4秒 >= 0.35秒で自動開始
    }
    @MainActor
    @Test func simulatedRecorderIsRecordingClipTrueImmediatelyAfterStart() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.startClipRecording()

        // startClipRecording() 呼び出し直後に isRecordingClip が true になること
        #expect(recorder.isRecordingClip)
    }

    @MainActor
    @Test func simulatedRecorderStopImmediatelyAfterStartSavesFile() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        recorder.startClipRecording()
        recorder.stopClipRecording()  // 即座に停止

        #expect(!recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName?.hasSuffix(".m4a") == true)
        #expect(recorder.errorMessage == nil)
    }

    #if DEBUG
    @MainActor
    @Test func motionSuppressionPreventsRecordingStartDuringPhysicalHandling() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        // 端末を動かした直後の状態を模擬
        recorder.simulateMotionSuppression(until: Date().addingTimeInterval(1.5))

        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 600.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 600.4))

        #expect(!recorder.isRecordingClip)
    }

    @MainActor
    @Test func motionSuppressionResetsAccumulatedPossibleSpeech() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        // possibleSpeech に入った後、モーションを検出
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 700.0))
        recorder.simulateMotionSuppression(until: Date().addingTimeInterval(1.5))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 700.4))

        #expect(!recorder.isRecordingClip)
    }

    @MainActor
    @Test func motionSuppressionDoesNotStopActiveRecording() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        recorder.startClipRecording()
        #expect(recorder.isRecordingClip)

        // 録音中に端末を動かしても停止しない
        recorder.simulateMotionSuppression(until: Date().addingTimeInterval(1.5))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 800.0))

        #expect(recorder.isRecordingClip)
    }
    #endif

    @MainActor
    @Test func dismissErrorClearsErrorMessage() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.errorMessage = "dummy"

        recorder.dismissError()

        #expect(recorder.errorMessage == nil)
    }

    // MARK: - VAD 一時停止（V-6/V-7/V-8）

    @MainActor
    @Test func vadPausePreventsAutoStart() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        recorder.setVADPaused(true)

        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1000.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1000.4))

        #expect(!recorder.isRecordingClip)
    }

    @MainActor
    @Test func vadPauseStopsActiveRecording() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        recorder.startClipRecording()
        #expect(recorder.isRecordingClip)

        recorder.setVADPaused(true)

        #expect(!recorder.isRecordingClip)
        #expect(recorder.isVADPaused)
    }

    @MainActor
    @Test func vadResumeAfterPauseAllowsAutoStart() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        recorder.setVADPaused(true)
        recorder.setVADPaused(false)

        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1100.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1100.4))

        #expect(recorder.isRecordingClip)
    }

    // MARK: - possibleEnd → 会話再開（V-3）

    @MainActor
    @Test func possibleEndResumesToInConversationWhenSpeechReturns() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        // 会話を開始
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1200.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1200.4))
        #expect(recorder.isRecordingClip)

        // 沈黙 → possibleEnd
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1201.0))

        // 会話再開 → inConversation に戻り stateChangedAt がリセットされる
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1202.0))

        // 再開から 4.9s の沈黙（合計 5s 未満）→ まだ録音中
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1203.0))
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1206.9))

        #expect(recorder.isRecordingClip)
    }

    @MainActor
    @Test func possibleEndStopsRecordingAfterSilenceWindowFromResume() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        // 会話を開始
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1300.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1300.4))

        // 沈黙 → possibleEnd
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1301.0))

        // 会話再開 → inConversation（stateChangedAt = 1302）
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1302.0))

        // 再開から 5.1s の沈黙 → 停止
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1303.0))
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1307.2))

        #expect(!recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName?.hasSuffix(".m4a") == true)
    }

    // MARK: - モーション抑制の期限切れ（M-4）

    #if DEBUG
    @MainActor
    @Test func recordingStartsAfterMotionSuppressionExpires() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        // 抑制ウィンドウをすでに過去に設定（期限切れ）
        recorder.simulateMotionSuppression(until: Date().addingTimeInterval(-0.1))

        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1400.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1400.4))

        #expect(recorder.isRecordingClip)
    }
    #endif

    // MARK: - 高速スタート/ストップの安定性（C-2/C-3）

    @MainActor
    @Test func rapidStartStopCyclesDoNotCorruptState() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        for _ in 0..<5 {
            recorder.startClipRecording()
            recorder.stopClipRecording()
        }

        #expect(!recorder.isRecordingClip)
        #expect(recorder.errorMessage == nil)
        #expect(recorder.canControlRecording)
    }

    @MainActor
    @Test func secondRecordingCycleWorksAfterFirstCompletes() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()

        // 1サイクル目：VAD 自動開始→自動停止
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1500.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1500.4))
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1501.0))
        recorder.handleVoiceActivityScore(0.3, timestamp: Date(timeIntervalSince1970: 1506.1))
        #expect(!recorder.isRecordingClip)
        let firstFile = recorder.lastSavedFileName
        #expect(firstFile != nil)

        // 2サイクル目：同様に自動開始できる
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1510.0))
        recorder.handleVoiceActivityScore(0.9, timestamp: Date(timeIntervalSince1970: 1510.4))
        #expect(recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName == nil) // 新しいクリップ開始直後はnil
    }
}
