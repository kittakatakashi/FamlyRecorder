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
    // 生成済みダイジェストURLのキャッシュ（レンダリング毎のファイルシステムI/Oを防ぐ）
    @Published private(set) var existingDigestURLs: Set<URL> = []
    @Published var generationError: String?

    static let maxDuration: TimeInterval = 120
    private static let snippetDuration: TimeInterval = 20

    private static let digestDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    init() {
        refreshExistingDigests()
    }

    func exists(for day: Date) -> Bool {
        guard let url = try? RecordingFileStore.digestURL(for: day) else { return false }
        return existingDigestURLs.contains(url)
    }

    func digestURL(for day: Date) -> URL? {
        guard let url = try? RecordingFileStore.digestURL(for: day),
              existingDigestURLs.contains(url) else { return nil }
        return url
    }

    func refreshExistingDigests() {
        guard let dir = try? RecordingFileStore.digestDirectoryURL() else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        existingDigestURLs = Set(urls.filter { $0.pathExtension == "m4a" && $0.lastPathComponent.hasPrefix("digest-") })
    }

    func generate(for day: Date, items: [RecordingItem]) async {
        guard !generatingDays.contains(day) else { return }
        generatingDays.insert(day)
        defer { generatingDays.remove(day) }

        guard let outputURL = try? RecordingFileStore.digestURL(for: day) else { return }
        try? FileManager.default.removeItem(at: outputURL)

        let chronologicalItems = items.sorted { $0.date < $1.date }

        // 各クリップのassetとdurationを一度だけロード
        var chronologicalClips: [(asset: AVURLAsset, duration: CMTime)] = []
        for item in chronologicalItems {
            let asset = AVURLAsset(url: item.url)
            guard let dur = try? await asset.load(.duration), dur.seconds > 0 else { continue }
            chronologicalClips.append((asset, dur))
        }
        guard !chronologicalClips.isEmpty else { return }

        // 長い順で選択し、各クリップから先頭snippetDuration秒を取る（合計maxDuration秒上限）
        let byDuration = chronologicalClips.sorted { $0.duration.seconds > $1.duration.seconds }
        var selectedIDs = Set<ObjectIdentifier>()
        var accumulated: TimeInterval = 0
        for clip in byDuration {
            guard accumulated < Self.maxDuration else { break }
            selectedIDs.insert(ObjectIdentifier(clip.asset))
            accumulated += min(clip.duration.seconds, Self.snippetDuration)
        }

        // 時系列順に並び替えてから結合（選択済みassetをそのまま再利用、再生成しない）
        let orderedClips = chronologicalClips.filter { selectedIDs.contains(ObjectIdentifier($0.asset)) }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return }

        var cursor = CMTime.zero
        for clip in orderedClips {
            guard let srcTrack = try? await clip.asset.loadTracks(withMediaType: .audio).first else { continue }
            let trimSec = min(clip.duration.seconds, Self.snippetDuration)
            let trimmedDuration = CMTime(seconds: trimSec, preferredTimescale: 44100)
            let srcRange = CMTimeRange(start: .zero, duration: trimmedDuration)
            do {
                try track.insertTimeRange(srcRange, of: srcTrack, at: cursor)
                cursor = CMTimeAdd(cursor, trimmedDuration)
            } catch {
                continue  // 失敗したclipはスキップ。cursorは進めない
            }
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return }

        do {
            try await exporter.export(to: outputURL, as: .m4a)
            refreshExistingDigests()
        } catch {
            generationError = "ダイジェストの生成に失敗しました"
        }
    }
}
