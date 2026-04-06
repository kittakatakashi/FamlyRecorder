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

    @Test func timedRingBufferTrimsOldEntriesBeyondMaxDuration() {
        var buffer = TimedRingBuffer<String>()

        buffer.append("first", duration: 12, keepingMaxDuration: 30)
        buffer.append("second", duration: 10, keepingMaxDuration: 30)
        buffer.append("third", duration: 11, keepingMaxDuration: 30)

        #expect(buffer.entries.map(\.element) == ["second", "third"])
        #expect(buffer.totalDuration == 21)
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

    @Test func recordingFileStoreBuildsStableWavFileName() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let date = Date(timeIntervalSince1970: 0)

        let url = RecordingFileStore.outputURL(in: directory, date: date)

        #expect(url.path == "/tmp/recording-19700101-000000.wav")
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
    @Test func simulatedRecorderStatusTextReflectsRecordingState() {
        let recorder = RecorderManager(mode: .simulated)
        recorder.prepare()
        #expect(recorder.recordingStatusText.contains("待機中"))

        recorder.startClipRecording()
        #expect(recorder.recordingStatusText.contains("録音中"))
    }

}
