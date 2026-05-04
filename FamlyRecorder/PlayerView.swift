//
//  PlayerView.swift
//  FamlyRecorder
//

import SwiftUI

struct PlayerView: View {
    @ObservedObject var player: RecordingPlayer
    @ObservedObject var transcriptionStore: TranscriptionStore
    @State private var items: [RecordingItem]
    @State private var currentIndex: Int
    @State private var showDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    let onDelete: (RecordingItem) -> Void

    init(allItems: [RecordingItem], startIndex: Int, player: RecordingPlayer, transcriptionStore: TranscriptionStore, onDelete: @escaping (RecordingItem) -> Void) {
        self._items = State(initialValue: allItems)
        self._currentIndex = State(initialValue: startIndex)
        self._player = ObservedObject(wrappedValue: player)
        self._transcriptionStore = ObservedObject(wrappedValue: transcriptionStore)
        self.onDelete = onDelete
    }

    private var currentItem: RecordingItem { items[currentIndex] }
    private var hasNext: Bool { currentIndex < items.count - 1 }
    private var hasPrev: Bool { currentIndex > 0 }

    private var isPlaying: Bool { player.playingURL == currentItem.url && player.isPlaying }
    private var isLoaded: Bool  { player.playingURL == currentItem.url }
    private var currentTime: TimeInterval { isLoaded ? player.currentTime : 0 }
    private var totalDuration: TimeInterval { isLoaded ? player.duration : currentItem.duration }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text(currentItem.date, format: .dateTime.year().month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(currentItem.date, format: .dateTime.hour().minute())
                    .font(.system(size: 52, weight: .bold, design: .rounded))
            }

            transcriptionArea

            Spacer()

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(totalDuration, 1)
                )
                .tint(.orange)

                HStack {
                    Text(formatTime(currentTime))
                    Spacer()
                    Text(formatTime(totalDuration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 32) {
                Button {
                    skipTo(currentIndex - 1)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                .tint(.primary)
                .disabled(!hasPrev)

                Button {
                    player.seek(to: max(0, currentTime - 15))
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                }
                .tint(.primary)

                Button {
                    player.toggle(url: currentItem.url)
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                .tint(.orange)

                Button {
                    player.seek(to: min(totalDuration, currentTime + 15))
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title)
                }
                .tint(.primary)

                Button {
                    skipTo(currentIndex + 1)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                }
                .tint(.primary)
                .disabled(!hasNext)
            }

            Spacer()
        }
        .navigationTitle("録音再生")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)
            }
        }
        .alert("録音を削除しますか？", isPresented: $showDeleteAlert) {
            Button("削除", role: .destructive) { deleteCurrentItem() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .onAppear { player.play(url: currentItem.url) }
        .onDisappear { player.stop() }
        .onChange(of: player.finishedPlayingURL) { _, finishedURL in
            guard finishedURL == currentItem.url, hasNext else { return }
            skipTo(currentIndex + 1)
        }
    }

    @ViewBuilder
    private var transcriptionArea: some View {
        let state = transcriptionStore.state(for: currentItem.url)
        let text = transcriptionStore.text(for: currentItem.url)

        if let text, state == .draft || state == .final {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if state == .final {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("確定変換")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: "text.bubble")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("仮変換")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 120)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
    }

    private func skipTo(_ index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        player.play(url: currentItem.url)
    }

    private func deleteCurrentItem() {
        let item = currentItem
        player.stop()
        try? FileManager.default.removeItem(at: item.url)
        onDelete(item)
        items.remove(at: currentIndex)
        if items.isEmpty {
            dismiss()
        } else {
            let newIndex = min(currentIndex, items.count - 1)
            currentIndex = newIndex
            player.play(url: currentItem.url)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
