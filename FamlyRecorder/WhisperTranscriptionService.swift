//
//  WhisperTranscriptionService.swift
//  FamlyRecorder
//

import Foundation

enum WhisperError: LocalizedError {
    case missingAPIKey
    case fileTooLarge
    case httpError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:    return "Whisper APIキーが設定されていません。"
        case .fileTooLarge:    return "ファイルサイズが上限（25MB）を超えています。"
        case .httpError(let code, let msg): return "APIエラー \(code): \(msg)"
        case .decodingError:   return "レスポンスの解析に失敗しました。"
        }
    }
}

struct WhisperTranscriptionService {
    static let apiKeyKeychainKey = "com.famlyrecorder.whisper-api-key"
    private static let model = "gpt-4o-mini-transcribe"
    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private static let fileSizeLimit = 25 * 1024 * 1024

    func transcribe(url: URL) async throws -> String {
        guard let apiKey = KeychainStore.load(forKey: Self.apiKeyKeychainKey), !apiKey.isEmpty else {
            throw WhisperError.missingAPIKey
        }

        let fileData = try Data(contentsOf: url)
        guard fileData.count <= Self.fileSizeLimit else {
            throw WhisperError.fileTooLarge
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildBody(fileData: fileData, fileName: url.lastPathComponent, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhisperError.decodingError }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw WhisperError.httpError(http.statusCode, msg)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw WhisperError.decodingError }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildBody(fileData: Data, fileName: String, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"

        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\(crlf)".utf8Data)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".utf8Data)
            body.append("\(value)\(crlf)".utf8Data)
        }

        field("model", Self.model)
        field("language", "ja")
        field("response_format", "text")

        body.append("--\(boundary)\(crlf)".utf8Data)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(crlf)".utf8Data)
        body.append("Content-Type: audio/wav\(crlf)\(crlf)".utf8Data)
        body.append(fileData)
        body.append("\(crlf)--\(boundary)--\(crlf)".utf8Data)

        return body
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
