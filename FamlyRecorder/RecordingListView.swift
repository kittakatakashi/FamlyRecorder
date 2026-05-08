//
//  RecordingListView.swift
//  FamlyRecorder
//

import AVFoundation
import SwiftUI

struct RecordingListView: View {
    let recorder: RecorderManager
    @StateObject private var player = RecordingPlayer()
    @StateObject private var transcriptionStore = TranscriptionStore()
    @StateObject private var digestStore = DigestStore()
    @State private var groups: [DayGroup] = []
    @State private var isLoading = true
    @State private var expandedPeriods: Set<String> = []
    @State private var itemToDelete: RecordingItem?
    @State private var showAPIKeyAlert = false
    @State private var apiKeyInput = ""
    @State private var pendingWhisperURL: URL?
    @Environment(\.scenePhase) private var scenePhase

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
        }
        .task { await loadRecordings() }
        .onChange(of: recorder.lastSavedFileURL) { _, _ in
            Task { await loadRecordings() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await loadRecordings() }
            }
        }
    }

    private var sortedAllItems: [RecordingItem] {
        groups.flatMap { $0.periods.flatMap { $0.items } }
            .sorted { $0.date < $1.date }
    }

    private var recordingList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.periods) { period in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedPeriods.contains(periodKey(group, period)) },
                                set: { open in
                                    let key = periodKey(group, period)
                                    if open { expandedPeriods.insert(key) } else { expandedPeriods.remove(key) }
                                }
                            )
                        ) {
                            ForEach(period.items) { item in
                                NavigationLink {
                                    PlayerView(
                                        allItems: sortedAllItems,
                                        startIndex: sortedAllItems.firstIndex(where: { $0.id == item.id }) ?? 0,
                                        player: player,
                                        transcriptionStore: transcriptionStore,
                                        onDelete: deleteItem
                                    )
                                } label: {
                                    RecordingRow(
                                        item: item,
                                        transcriptionState: transcriptionStore.state(for: item.url),
                                        transcriptionText: transcriptionStore.text(for: item.url),
                                        isTranscribing: transcriptionStore.isTranscribing(url: item.url),
                                        onRetry: {
                                            transcriptionStore.reset(url: item.url)
                                            Task { await transcriptionStore.transcribe(url: item.url) }
                                        },
                                        onWhisper: {
                                            triggerWhisper(url: item.url)
                                        }
                                    )
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        itemToDelete = item
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(period.label)
                                Spacer()
                                Text(formatTotalDuration(period.items))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.dayLabel)
                        Spacer()
                        digestButton(for: group)
                        Text(formatTotalDuration(group.periods.flatMap { $0.items }))
                            .fontWeight(.regular)
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadRecordings() }
        .alert("Whisper APIキー", isPresented: $showAPIKeyAlert) {
            SecureField("sk-...", text: $apiKeyInput)
            Button("保存して変換") {
                transcriptionStore.saveWhisperAPIKey(apiKeyInput)
                apiKeyInput = ""
                if let url = pendingWhisperURL {
                    pendingWhisperURL = nil
                    Task { await transcriptionStore.transcribeWithWhisper(url: url) }
                }
            }
            Button("キャンセル", role: .cancel) {
                apiKeyInput = ""
                pendingWhisperURL = nil
            }
        } message: {
            Text("OpenAI APIキーを入力してください。Keychainに安全に保存されます。")
        }
        .alert("録音を削除しますか？", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("削除", role: .destructive) {
                if let item = itemToDelete { deleteItem(item) }
                itemToDelete = nil
            }
            Button("キャンセル", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("この操作は取り消せません。")
        }
        .alert("エラー", isPresented: Binding(
            get: { digestStore.generationError != nil },
            set: { if !$0 { digestStore.generationError = nil } }
        )) {
            Button("OK", role: .cancel) { digestStore.generationError = nil }
        } message: {
            Text(digestStore.generationError ?? "")
        }
    }

    private func loadRecordings() async {
        isLoading = groups.isEmpty
        let loaded = await Task.detached(priority: .userInitiated) {
            await buildGroups()
        }.value
        groups = loaded
        isLoading = false
        if expandedPeriods.isEmpty, let g = loaded.first, let p = g.periods.first {
            expandedPeriods.insert(periodKey(g, p))
        }
        // startPendingTranscriptions() // 文字起こし機能を一時無効化
    }

    private func startPendingTranscriptions() {
        let items = groups.flatMap { $0.periods.flatMap { $0.items } }
            .filter { transcriptionStore.state(for: $0.url) == .none }
        Task {
            for item in items {
                await transcriptionStore.transcribe(url: item.url)
            }
        }
    }

    private func formatTotalDuration(_ items: [RecordingItem]) -> String {
        let rawTotal = items.reduce(0) { $0 + $1.duration }
        guard rawTotal.isFinite, rawTotal >= 0 else { return "--:--" }
        let total = Int(rawTotal)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func periodKey(_ group: DayGroup, _ period: PeriodGroup) -> String {
        "\(group.id.timeIntervalSince1970)-\(period.id)"
    }

    @ViewBuilder
    private func digestButton(for group: DayGroup) -> some View {
        if digestStore.generatingDays.contains(group.id) {
            ProgressView().scaleEffect(0.7)
        } else if let url = digestStore.digestURL(for: group.id) {
            Button {
                player.play(url: url)
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await digestStore.generate(for: group.id, items: group.allItems) }
            } label: {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func triggerWhisper(url: URL) {
        if transcriptionStore.isWhisperKeySet {
            Task { await transcriptionStore.transcribeWithWhisper(url: url) }
        } else {
            pendingWhisperURL = url
            showAPIKeyAlert = true
        }
    }

    private func deleteItem(_ item: RecordingItem) {
        try? FileManager.default.removeItem(at: item.url)
        groups = groups.compactMap { day in
            let periods = day.periods.compactMap { period in
                let items = period.items.filter { $0.id != item.id }
                return items.isEmpty ? nil : PeriodGroup(id: period.id, label: period.label, items: items)
            }
            return periods.isEmpty ? nil : DayGroup(id: day.id, dayLabel: day.dayLabel, periods: periods)
        }
    }
}

// MARK: - Row

private struct RecordingRow: View {
    let item: RecordingItem
    let transcriptionState: TranscriptionState
    let transcriptionText: String?
    let isTranscribing: Bool
    let onRetry: () -> Void
    let onWhisper: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.date, format: .dateTime.hour().minute())
                    .font(.body.monospacedDigit())
                Text(formatDuration(item.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                // transcriptionBadge // 文字起こし機能を一時無効化
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var transcriptionBadge: some View {
        if isTranscribing {
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("文字起こし中...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if transcriptionState == .final, let text = transcriptionText {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if let text = transcriptionText, transcriptionState == .draft {
            HStack(spacing: 6) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(action: onWhisper) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        } else if transcriptionState == .failed {
            HStack(spacing: 8) {
                Button(action: onRetry) {
                    Label("再試行", systemImage: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                Button(action: onWhisper) {
                    Label("Whisper", systemImage: "wand.and.stars")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
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
    var allItems: [RecordingItem] { periods.flatMap { $0.items } }
}

private struct PeriodGroup: Identifiable {
    let id: String
    let label: String
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
    for url in urls where ["wav", "m4a"].contains(url.pathExtension) && FileManager.default.fileExists(atPath: url.path) {
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

    let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "H時"
        return f
    }()

    let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.date) }
    return byDay.keys.sorted(by: >).map { day in
        let dayItems = byDay[day]!
        let byHour = Dictionary(grouping: dayItems) { cal.component(.hour, from: $0.date) }
        let periods = byHour.keys.sorted(by: >).map { hour -> PeriodGroup in
            let ref = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            return PeriodGroup(id: "\(hour)", label: hourFormatter.string(from: ref), items: byHour[hour]!.sorted { $0.date > $1.date })
        }
        return DayGroup(id: day, dayLabel: dayFormatter.string(from: day), periods: periods)
    }
}
