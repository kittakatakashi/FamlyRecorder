//
//  RecordingListView.swift
//  FamlyRecorder
//

import AVFoundation
import SwiftUI

struct RecordingListView: View {
    @StateObject private var player = RecordingPlayer()
    @State private var groups: [DayGroup] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groups.isEmpty {
                    ContentUnavailableView(
                        "録音がありません",
                        systemImage: "waveform.slash",
                        description: Text("「録音」タブから録音を開始してください。")
                    )
                } else {
                    recordingList
                }
            }
            .navigationTitle("録音一覧")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if player.playingURL != nil {
                        Button("停止") { player.stop() }
                    }
                }
            }
        }
        .task { await loadRecordings() }
    }

    private var recordingList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.periods) { period in
                        Section(period.label) {
                            ForEach(period.items) { item in
                                RecordingRow(item: item, player: player)
                            }
                        }
                    }
                } header: {
                    Text(group.dayLabel)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadRecordings() }
    }

    private func loadRecordings() async {
        isLoading = groups.isEmpty
        let loaded = await Task.detached(priority: .userInitiated) {
            await buildGroups()
        }.value
        groups = loaded
        isLoading = false
    }
}

// MARK: - Row

private struct RecordingRow: View {
    let item: RecordingItem
    @ObservedObject var player: RecordingPlayer

    private var isThisPlaying: Bool { player.playingURL == item.url && player.isPlaying }
    private var isThisLoaded: Bool  { player.playingURL == item.url }

    var body: some View {
        Button {
            player.toggle(url: item.url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isThisPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isThisPlaying ? .orange : .accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.date, format: .dateTime.hour().minute())
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary)

                    if isThisLoaded {
                        ProgressView(value: player.currentTime, total: max(player.duration, 1))
                            .tint(.orange)
                        HStack {
                            Text(formatDuration(player.currentTime))
                            Spacer()
                            Text(formatDuration(player.duration))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    } else {
                        Text(formatDuration(item.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Data model

private struct DayGroup: Identifiable {
    let id: Date
    let dayLabel: String
    let periods: [PeriodGroup]
}

private struct PeriodGroup: Identifiable {
    let id: String
    var label: String { id }
    let items: [RecordingItem]
}

// MARK: - Loading

private func buildGroups() async -> [DayGroup] {
    guard let dir = try? RecordingFileStore.recordingsDirectoryURL() else { return [] }

    let urls = (try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil
    )) ?? []

    var items: [RecordingItem] = []
    for url in urls where url.pathExtension == "wav" {
        guard let date = RecordingFileStore.date(from: url.lastPathComponent) else { continue }
        let duration = await loadDuration(url: url)
        items.append(RecordingItem(url: url, date: date, duration: duration))
    }
    items.sort { $0.date > $1.date }

    return grouped(items)
}

private func loadDuration(url: URL) async -> TimeInterval {
    let asset = AVURLAsset(url: url)
    guard let cmDuration = try? await asset.load(.duration) else { return 0 }
    return cmDuration.seconds
}

private func grouped(_ items: [RecordingItem]) -> [DayGroup] {
    let cal = Calendar.current
    let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日（E）"
        return f
    }()

    let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
    return byDay.keys.sorted(by: >).map { day in
        let dayItems = byDay[day]!
        let byPeriod = Dictionary(grouping: dayItems) { periodLabel(for: $0.date) }
        let orderedLabels = ["朝 (5〜12時)", "昼 (12〜17時)", "夕方 (17〜20時)", "夜 (20〜5時)"]
        let periods = orderedLabels.compactMap { label -> PeriodGroup? in
            guard let its = byPeriod[label], !its.isEmpty else { return nil }
            return PeriodGroup(id: label, items: its)
        }
        return DayGroup(id: day, dayLabel: dayFormatter.string(from: day), periods: periods)
    }
}

private func periodLabel(for date: Date) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5..<12:  return "朝 (5〜12時)"
    case 12..<17: return "昼 (12〜17時)"
    case 17..<20: return "夕方 (17〜20時)"
    default:      return "夜 (20〜5時)"
    }
}
