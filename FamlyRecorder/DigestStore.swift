//
//  DigestStore.swift
//  FamlyRecorder
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class DigestStore: ObservableObject {
    @Published private(set) var generatingDays: Set<Date> = []

    // 1日のダイジェスト上限（秒）
    static let maxDuration: TimeInterval = 120
    // 各クリップから取り出す秒数
    private static let snippetDuration: TimeInterval = 20

    func exists(for day: Date) -> Bool {
        guard let url = try? RecordingFileStore.digestURL(for: day) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func digestURL(for day: Date) -> URL? {
        try? RecordingFileStore.digestURL(for: day)
    }

    func generate(for day: Date, items: [RecordingItem]) async {
        guard !generatingDays.contains(day) else { return }
        generatingDays.insert(day)
        defer { generatingDays.remove(day) }

        guard let outputURL = try? RecordingFileStore.digestURL(for: day) else { return }
        try? FileManager.default.removeItem(at: outputURL)

        // 時系列昇順（出力順の基準）
        let sorted = items.sorted { $0.date < $1.date }

        // 各クリップのdurationを取得
        var clips: [(url: URL, duration: CMTime)] = []
        for item in sorted {
            let asset = AVURLAsset(url: item.url)
            guard let dur = try? await asset.load(.duration), dur.seconds > 0 else { continue }
            clips.append((item.url, dur))
        }
        guard !clips.isEmpty else { return }

        // 長い順で選択し、各クリップから先頭snippetDuration秒を取る（合計maxDuration秒上限）
        let byDuration = clips.sorted { $0.duration.seconds > $1.duration.seconds }
        var selectedURLs: [URL] = []
        var accumulated: TimeInterval = 0
        for clip in byDuration {
            guard accumulated < Self.maxDuration else { break }
            selectedURLs.append(clip.url)
            accumulated += min(clip.duration.seconds, Self.snippetDuration)
        }

        // 時系列順に並び替えてから結合
        let orderedClips = clips.filter { selectedURLs.contains($0.url) }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return }

        var cursor = CMTime.zero
        for clip in orderedClips {
            let asset = AVURLAsset(url: clip.url)
            guard let srcTrack = try? await asset.loadTracks(withMediaType: .audio).first else { continue }
            let trimSec = min(clip.duration.seconds, Self.snippetDuration)
            let trimmedDuration = CMTime(seconds: trimSec, preferredTimescale: 44100)
            let srcRange = CMTimeRange(start: .zero, duration: trimmedDuration)
            try? track.insertTimeRange(srcRange, of: srcTrack, at: cursor)
            cursor = CMTimeAdd(cursor, trimmedDuration)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return }
        try? await exporter.export(to: outputURL, as: .m4a)
    }
}
