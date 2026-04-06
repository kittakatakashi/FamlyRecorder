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

enum RecordingFileStore {
    static func outputURL(in directory: URL, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "recording-\(formatter.string(from: date)).wav"
        return directory.appendingPathComponent(fileName)
    }
}
