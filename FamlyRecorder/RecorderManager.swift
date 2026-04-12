//
//  RecorderManager.swift
//  FamlyRecorder
//
//  Created by Codex on 2026/04/05.
//

@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
final class RecorderManager: ObservableObject {
    enum Mode {
        case live
        case simulated
    }

    enum ConversationState {
        case idle
        case possibleSpeech
        case inConversation
        case possibleEnd
    }

    @Published private(set) var isPrepared = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isRecordingClip = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var bufferedSeconds: TimeInterval = 0
    @Published private(set) var lastSavedFileName: String?
    @Published private(set) var isLowPowerBackgroundMode = false
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "FamlyRecorder.audio-processing")
    private let ringBufferDuration: TimeInterval = 30
    private let preRecordDuration: TimeInterval = 15
    private let conversationStartThreshold: Float = 0.65
    private let conversationContinueThreshold: Float = 0.45
    private let minimumSpeechDurationToStart: TimeInterval = 0.35
    private let silenceDurationToStop: TimeInterval = 1.2
    private let foregroundIOBufferDuration: TimeInterval = 0.02
    private let backgroundIOBufferDuration: TimeInterval = 0.12
    private let foregroundVADStride = 1
    private let backgroundVADStride = 4
    private let foregroundStatusUpdateInterval: TimeInterval = 0.08
    private let backgroundStatusUpdateInterval: TimeInterval = 1.0
    private let recordingsDirectoryName = "FamlyRecorder"
    private let mode: Mode

    private var audioFormat: AVAudioFormat?
    private var ringBuffer = TimedRingBuffer<AVAudioPCMBuffer>()
    private var activeWriter: AVAudioFile?
    private var activeRecordingURL: URL?
    private var hasInstalledTap = false
    private var voiceActivityDetector = VoiceActivityDetector()
    private var conversationState: ConversationState = .idle
    private var stateChangedAt: Date?
    private var processedBufferCount = 0
    private var lastStatusUpdateAt: Date = .distantPast

    init(mode: Mode = .live) {
        self.mode = mode
    }

    var canControlRecording: Bool {
        permissionGranted && isPrepared && isBuffering
    }

    var permissionStatusText: String {
        permissionGranted ? "マイク許可済み。起動後すぐ常時録音バッファを維持します。" : "マイク許可が必要です。初回起動時に許可してください。"
    }

    var bufferStatusText: String {
        let seconds = min(bufferedSeconds, ringBufferDuration)
        if isBuffering {
            return String(format: "バッファ中: 過去 %.1f / %.0f 秒を保持", seconds, ringBufferDuration)
        }
        return "バッファを準備中です。"
    }

    var recordingStatusText: String {
        isRecordingClip ? "録音中: 会話を検知して保存中です。" : "待機中: 会話を検知すると自動で録音を開始します。"
    }

    var energyModeStatusText: String {
        isLowPowerBackgroundMode ? "省電力モード: バックグラウンド最適化中" : "通常モード: 前景で高感度検知中"
    }

    func prepare() {
        guard !isPrepared else { return }

        if mode == .simulated {
            permissionGranted = true
            isPrepared = true
            isBuffering = true
            bufferedSeconds = ringBufferDuration
            return
        }

        Task {
            do {
                let granted = try await requestPermission()
                permissionGranted = granted

                guard granted else {
                    errorMessage = "マイクへのアクセスが許可されていません。設定アプリからマイクを有効にしてください。"
                    return
                }

                try configureAudioSession()
                try installTapIfNeeded()
                try engine.start()
                isPrepared = true
                isBuffering = true
            } catch {
                errorMessage = "録音の準備に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    func setBackgroundMode(enabled: Bool) {
        guard mode == .live else { return }
        guard isLowPowerBackgroundMode != enabled else { return }

        isLowPowerBackgroundMode = enabled

        processingQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureAudioSession()
            } catch {
                Task { @MainActor in
                    self.errorMessage = "バックグラウンド設定の更新に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    func startClipRecording() {
        guard canControlRecording else { return }
        guard !isRecordingClip else { return }

        if mode == .simulated {
            do {
                let destination = try makeOutputURL()
                activeRecordingURL = destination
                isRecordingClip = true
                lastSavedFileName = nil
            } catch {
                errorMessage = "録音開始に失敗しました: \(error.localizedDescription)"
            }
            return
        }

        processingQueue.async { [weak self] in
            guard let self else { return }

            do {
                let format = try self.requireAudioFormat()
                let destination = try self.makeOutputURL()
                let writer = try AVAudioFile(forWriting: destination, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                let preRoll = self.collectBufferedAudio(last: self.preRecordDuration, format: format)

                for chunk in preRoll {
                    try writer.write(from: chunk)
                }

                self.activeWriter = writer
                self.activeRecordingURL = destination

                Task { @MainActor in
                    self.isRecordingClip = true
                    self.lastSavedFileName = nil
                }
            } catch {
                Task { @MainActor in
                    self.errorMessage = "録音開始に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    func stopClipRecording() {
        guard isRecordingClip else { return }

        if mode == .simulated {
            let savedURL = activeRecordingURL
            activeRecordingURL = nil
            isRecordingClip = false
            lastSavedFileName = savedURL?.lastPathComponent
            conversationState = .idle
            stateChangedAt = nil
            return
        }

        processingQueue.async { [weak self] in
            guard let self else { return }

            let savedURL = self.activeRecordingURL
            self.activeWriter = nil
            self.activeRecordingURL = nil
            let savedFileName = self.resolvedSavedFileName(from: savedURL)

            Task { @MainActor in
                self.isRecordingClip = false
                self.lastSavedFileName = savedFileName
                self.conversationState = .idle
                self.stateChangedAt = nil

                if savedURL != nil, savedFileName == nil {
                    self.errorMessage = "録音ファイルの保存確認に失敗しました。空き容量と権限を確認してください。"
                }
            }
        }
    }


    func handleVoiceActivityScore(_ score: Float, timestamp: Date = Date()) {
        guard canControlRecording else { return }

        switch conversationState {
        case .idle:
            guard score >= conversationStartThreshold else { return }
            conversationState = .possibleSpeech
            stateChangedAt = timestamp

        case .possibleSpeech:
            if score < conversationContinueThreshold {
                conversationState = .idle
                stateChangedAt = nil
                return
            }

            let elapsed = timestamp.timeIntervalSince(stateChangedAt ?? timestamp)
            if elapsed >= minimumSpeechDurationToStart {
//                if !isRecordingClip {
//                    startClipRecording()
//                }
                conversationState = .inConversation
                stateChangedAt = timestamp
            }

        case .inConversation:
            if score < conversationContinueThreshold {
                conversationState = .possibleEnd
                stateChangedAt = timestamp
            }

        case .possibleEnd:
            if score >= conversationStartThreshold {
                conversationState = .inConversation
                stateChangedAt = timestamp
                return
            }

            let elapsed = timestamp.timeIntervalSince(stateChangedAt ?? timestamp)
            if elapsed >= silenceDurationToStop {
//                if isRecordingClip {
//                    stopClipRecording()
//                }
                conversationState = .idle
                stateChangedAt = nil
            }
        }
    }

    func handleVoiceActivitySample(isSpeechDetected: Bool, timestamp: Date = Date()) {
        handleVoiceActivityScore(isSpeechDetected ? 1 : 0, timestamp: timestamp)
    }

    func dismissError() {
        errorMessage = nil
    }

    private func requestPermission() async throws -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try audioSession.setPreferredSampleRate(44_100)
        let preferredBuffer = isLowPowerBackgroundMode ? backgroundIOBufferDuration : foregroundIOBufferDuration
        try audioSession.setPreferredIOBufferDuration(preferredBuffer)
        try audioSession.setActive(true, options: [])
    }

    private func installTapIfNeeded() throws {
        guard !hasInstalledTap else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        audioFormat = inputFormat

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleIncomingBuffer(buffer)
        }

        hasInstalledTap = true
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let copiedBuffer = copyBuffer(buffer) else { return }

        processingQueue.async { [weak self] in
            guard let self else { return }

            let duration = self.duration(for: copiedBuffer)
            self.ringBuffer.append(copiedBuffer, duration: duration, keepingMaxDuration: self.ringBufferDuration)
            self.processedBufferCount += 1

            if let writer = self.activeWriter {
                do {
                    try writer.write(from: copiedBuffer)
                } catch {
                    self.activeWriter = nil
                    self.activeRecordingURL = nil
                    Task { @MainActor in
                        self.isRecordingClip = false
                        self.errorMessage = "録音データの書き込みに失敗しました: \(error.localizedDescription)"
                    }
                }
            }

            let vadStride = self.isLowPowerBackgroundMode ? self.backgroundVADStride : self.foregroundVADStride
            if self.processedBufferCount % vadStride == 0 {
                let score = self.voiceActivityDetector.score(for: copiedBuffer)
                Task { @MainActor in
                    self.handleVoiceActivityScore(score)
                }
            }

            let now = Date()
            let statusInterval = self.isLowPowerBackgroundMode ? self.backgroundStatusUpdateInterval : self.foregroundStatusUpdateInterval
            guard now.timeIntervalSince(self.lastStatusUpdateAt) >= statusInterval else { return }
            self.lastStatusUpdateAt = now

            Task { @MainActor in
                self.isBuffering = true
                self.bufferedSeconds = self.ringBuffer.totalDuration
            }
        }
    }

    private func collectBufferedAudio(last seconds: TimeInterval, format: AVAudioFormat) -> [AVAudioPCMBuffer] {
        ringBuffer.suffix(coveringLast: seconds).map { selection in
            trimBufferFront(selection.element, trimming: selection.trimLeadingDuration, format: format)
        }
    }

    private func trimBufferFront(_ buffer: AVAudioPCMBuffer, trimming seconds: TimeInterval, format: AVAudioFormat) -> AVAudioPCMBuffer {
        guard seconds > 0 else { return buffer }

        let framesToTrim = AVAudioFrameCount(seconds * format.sampleRate)
        guard framesToTrim > 0, framesToTrim < buffer.frameLength else { return buffer }

        let remainingFrames = buffer.frameLength - framesToTrim
        guard let trimmedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: remainingFrames) else {
            return buffer
        }

        trimmedBuffer.frameLength = remainingFrames

        if let source = buffer.floatChannelData, let destination = trimmedBuffer.floatChannelData {
            let channelCount = Int(format.channelCount)
            let sourceOffset = Int(framesToTrim)
            let frameCount = Int(remainingFrames)

            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel] + sourceOffset, count: frameCount)
            }

            return trimmedBuffer
        }

        if let source = buffer.int16ChannelData, let destination = trimmedBuffer.int16ChannelData {
            let channelCount = Int(format.channelCount)
            let sourceOffset = Int(framesToTrim)
            let frameCount = Int(remainingFrames)

            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel] + sourceOffset, count: frameCount)
            }

            return trimmedBuffer
        }

        if let source = buffer.int32ChannelData, let destination = trimmedBuffer.int32ChannelData {
            let channelCount = Int(format.channelCount)
            let sourceOffset = Int(framesToTrim)
            let frameCount = Int(remainingFrames)

            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel] + sourceOffset, count: frameCount)
            }

            return trimmedBuffer
        }

        return buffer
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = audioFormat ?? buffer.format

        guard let clone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }

        clone.frameLength = buffer.frameLength
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)

        if let source = buffer.floatChannelData, let destination = clone.floatChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return clone
        }

        if let source = buffer.int16ChannelData, let destination = clone.int16ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return clone
        }

        if let source = buffer.int32ChannelData, let destination = clone.int32ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return clone
        }

        return nil
    }

    private func duration(for buffer: AVAudioPCMBuffer) -> TimeInterval {
        TimeInterval(buffer.frameLength) / buffer.format.sampleRate
    }


    private func requireAudioFormat() throws -> AVAudioFormat {
        if let audioFormat {
            return audioFormat
        }

        throw RecorderError.audioFormatUnavailable
    }

    private func makeOutputURL() throws -> URL {
        let documentsURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let recordingsDirectoryURL = documentsURL.appendingPathComponent(recordingsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let baseURL = RecordingFileStore.outputURL(in: recordingsDirectoryURL, date: Date())
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var suffix = 1

        while true {
            let candidateName = "\(baseName)-\(suffix)"
            let candidateURL = recordingsDirectoryURL
                .appendingPathComponent(candidateName)
                .appendingPathExtension(ext)

            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }

    private func resolvedSavedFileName(from savedURL: URL?) -> String? {
        guard let savedURL else { return nil }
        let path = savedURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attributes[.size] as? NSNumber,
            size.intValue > 0
        else {
            return nil
        }

        return savedURL.lastPathComponent
    }
}

private enum RecorderError: LocalizedError {
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .audioFormatUnavailable:
            return "音声フォーマットを取得できませんでした。"
        }
    }
}
