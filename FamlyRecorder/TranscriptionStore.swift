//
//  TranscriptionStore.swift
//  FamlyRecorder

import Combine
import Foundation
import Speech

// MARK: - Models

struct RecordingMetadata: Codable {
    let fileName: String
    var transcriptionState: TranscriptionState
    var text: String?
}

enum TranscriptionState: String, Codable {
    case none
    case draft    // SFSpeechRecognizer 完了
    case final    // Whisper API 完了（#17）
    case failed
}

// MARK: - Store

@MainActor
final class TranscriptionStore: ObservableObject {
    @Published private(set) var metadata: [String: RecordingMetadata] = [:]
    @Published private(set) var transcribingFileNames: Set<String> = []

    private let jsonURL: URL?

    init() {
        jsonURL = try? RecordingFileStore.recordingsDirectoryURL()
            .appendingPathComponent("transcriptions.json")
        load()
    }

    func state(for url: URL) -> TranscriptionState {
        metadata[url.lastPathComponent]?.transcriptionState ?? .none
    }

    func isTranscribing(url: URL) -> Bool {
        transcribingFileNames.contains(url.lastPathComponent)
    }

    func text(for url: URL) -> String? {
        metadata[url.lastPathComponent]?.text
    }

    func transcribe(url: URL) async {
        let fileName = url.lastPathComponent
        guard state(for: url) == .none, !transcribingFileNames.contains(fileName) else { return }

        transcribingFileNames.insert(fileName)
        defer { transcribingFileNames.remove(fileName) }

        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else {
            update(fileName: fileName, state: .failed, text: nil)
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")),
              recognizer.isAvailable else {
            update(fileName: fileName, state: .failed, text: nil)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        do {
            let transcribed: String = try await withCheckedThrowingContinuation { cont in
                var resumed = false
                recognizer.recognitionTask(with: request) { result, error in
                    guard !resumed else { return }
                    if let error {
                        resumed = true
                        cont.resume(throwing: error)
                    } else if let result, result.isFinal {
                        resumed = true
                        cont.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
            update(fileName: fileName, state: .draft, text: transcribed)
        } catch {
            update(fileName: fileName, state: .failed, text: nil)
        }
    }

    private func update(fileName: String, state: TranscriptionState, text: String?) {
        metadata[fileName] = RecordingMetadata(fileName: fileName, transcriptionState: state, text: text)
        save()
    }

    private func load() {
        guard let url = jsonURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: RecordingMetadata].self, from: data)
        else { return }
        metadata = decoded
    }

    private func save() {
        guard let url = jsonURL,
              let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
