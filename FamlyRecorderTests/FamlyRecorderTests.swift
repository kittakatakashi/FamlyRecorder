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

    @Test func recordingFileStoreBuildsStableWavFileName() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let date = Date(timeIntervalSince1970: 0)

        let url = RecordingFileStore.outputURL(in: directory, date: date)

        #expect(url.path == "/tmp/recording-19700101-000000.wav")
    }

    @Test func recordingFileStoreUsesWavExtensionAndUtcTimestampFormat() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1_712_345_678)

        let url = RecordingFileStore.outputURL(in: directory, date: date)

        #expect(url.pathExtension == "wav")
        #expect(url.lastPathComponent.starts(with: "recording-"))
        #expect(url.lastPathComponent.contains("-"))
    }



    // MARK: - VoiceActivityDetector

    @Test func voiceActivityDetectorKeepsNoiseScoreLow() {
        var detector = VoiceActivityDetector()

        for _ in 0..<40 {
            _ = detector.score(forDecibel: -58)
        }

        let score = detector.score(forDecibel: -56)
        #expect(score < 0.35)
    }

    @Test func voiceActivityDetectorRaisesScoreForSpeechLikeLevel() {
        var detector = VoiceActivityDetector()

        for _ in 0..<40 {
            _ = detector.score(forDecibel: -60)
        }

        var score: Float = 0
        for _ in 0..<8 {
            score = detector.score(forDecibel: -24)
        }

        #expect(score > 0.7)
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
        #expect(recorder.bufferedSeconds == 30)
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
        #expect(recorder.bufferedSeconds == 30)
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
        #expect(recorder.lastSavedFileName?.hasSuffix(".wav") == true)
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

        #expect(firstSavedFile?.hasSuffix(".wav") == true)
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
        #expect(recorder.bufferStatusText.contains("30"))
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
        recorder.handleVoiceActivitySample(isSpeechDetected: false, timestamp: Date(timeIntervalSince1970: 202.3))

        #expect(!recorder.isRecordingClip)
        #expect(recorder.lastSavedFileName?.hasSuffix(".wav") == true)
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
        #expect(recorder.lastSavedFileName?.hasSuffix(".wav") == true)
        #expect(recorder.errorMessage == nil)
    }

    @MainActor
    @Test func dismissErrorClearsErrorMessage() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.errorMessage = "dummy"

        recorder.dismissError()

        #expect(recorder.errorMessage == nil)
    }
}
