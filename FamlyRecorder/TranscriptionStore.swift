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

    func reset(url: URL) {
        metadata.removeValue(forKey: url.lastPathComponent)
        save()
    }

    var isWhisperKeySet: Bool {
        let key = KeychainStore.load(forKey: WhisperTranscriptionService.apiKeyKeychainKey)
        return key != nil && !(key!.isEmpty)
    }

    func saveWhisperAPIKey(_ key: String) {
        KeychainStore.save(key, forKey: WhisperTranscriptionService.apiKeyKeychainKey)
    }

    func transcribeWithWhisper(url: URL) async {
        let fileName = url.lastPathComponent
        let currentState = state(for: url)
        guard currentState == .draft || currentState == .failed else { return }
        guard !transcribingFileNames.contains(fileName) else { return }

        transcribingFileNames.insert(fileName)
        defer { transcribingFileNames.remove(fileName) }

        do {
            let text = try await WhisperTranscriptionService().transcribe(url: url)
            if text.isEmpty {
                update(fileName: fileName, state: .failed, text: metadata[fileName]?.text)
            } else {
                update(fileName: fileName, state: .final, text: text)
            }
        } catch {
            // 失敗時は既存テキスト（draft）を保持してステートのみ変更する
            update(fileName: fileName, state: .failed, text: metadata[fileName]?.text)
        }
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
            if transcribed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                update(fileName: fileName, state: .failed, text: nil)
            } else {
                update(fileName: fileName, state: .draft, text: transcribed)
            }
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
