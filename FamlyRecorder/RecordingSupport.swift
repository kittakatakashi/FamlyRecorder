//
//  RecordingSupport.swift
//  FamlyRecorder
//
//  Created by Codex on 2026/04/05.
//

import Foundation

struct TimedRingBuffer<Element> {
    struct Entry {
        let element: Element
        let duration: TimeInterval
    }

    struct Selection {
        let element: Element
        let trimLeadingDuration: TimeInterval
    }

    private(set) var entries: [Entry] = []
    private(set) var totalDuration: TimeInterval = 0

    mutating func append(_ element: Element, duration: TimeInterval, keepingMaxDuration maxDuration: TimeInterval) {
        entries.append(Entry(element: element, duration: duration))
        totalDuration += duration
        trimIfNeeded(maxDuration: maxDuration)
    }

    func suffix(coveringLast targetDuration: TimeInterval) -> [Selection] {
        guard targetDuration > 0 else { return [] }

        var collected: TimeInterval = 0
        var selected: [Selection] = []

        for entry in entries.reversed() {
            collected += entry.duration
            let overflow = max(0, collected - targetDuration)
            selected.insert(Selection(element: entry.element, trimLeadingDuration: overflow), at: 0)

            if collected >= targetDuration {
                break
            }
        }

        if selected.count > 1 {
            for index in 1..<selected.count {
                selected[index] = Selection(element: selected[index].element, trimLeadingDuration: 0)
            }
        }

        return selected
    }

    private mutating func trimIfNeeded(maxDuration: TimeInterval) {
        while totalDuration > maxDuration, !entries.isEmpty {
            let removed = entries.removeFirst()
            totalDuration -= removed.duration
        }
    }
}

struct RecordingItem: Identifiable {
    let url: URL
    let date: Date
    let duration: TimeInterval
    var id: URL { url }
}

enum RecordingFileStore {
    // iCloud コンテナ URL（nil = 未設定またはオフライン）
    // prepareCloudDirectory() で一度だけ書き込み、以降は読み取り専用
    private nonisolated(unsafe) static var iCloudDirectoryURL: URL? = nil

    static var isUsingICloud: Bool { iCloudDirectoryURL != nil }

    // 起動時に一度呼ぶ。iCloud が利用可能なら URL を確定しローカルファイルを移行する
    static func prepareCloudDirectory() async {
        let containerURL = await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.kittaka.FamlyRecorder")
        }.value

        guard let containerURL else { return }

        let iCloudDir = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("FamilyRecorder", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: iCloudDir, withIntermediateDirectories: true)
        } catch { return }

        migrateLocalToICloud(iCloudDir: iCloudDir)
        iCloudDirectoryURL = iCloudDir
    }

    static func recordingsDirectoryURL() throws -> URL {
        if let iCloudDir = iCloudDirectoryURL { return iCloudDir }
        return try localRecordingsDirectoryURL()
    }

    static func localRecordingsDirectoryURL() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("FamilyRecorder", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // ローカルの録音ファイルを iCloud ディレクトリへ移動（重複はスキップ）
    private static func migrateLocalToICloud(iCloudDir: URL) {
        guard let localDir = try? localRecordingsDirectoryURL() else { return }
        guard localDir.path != iCloudDir.path else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: localDir, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let destination = iCloudDir.appendingPathComponent(file.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.moveItem(at: file, to: destination)
        }
    }

    static func outputURL(in directory: URL, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "recording-\(formatter.string(from: date)).wav"
        return directory.appendingPathComponent(fileName)
    }

    // "recording-yyyyMMdd-HHmmss.wav" および "-1" サフィックス付きに対応
    static func date(from fileName: String) -> Date? {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        guard base.hasPrefix("recording-"), base.count >= 25 else { return nil }
        let start = base.index(base.startIndex, offsetBy: 10)
        let end   = base.index(start, offsetBy: 15)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: String(base[start..<end]))
    }
}
