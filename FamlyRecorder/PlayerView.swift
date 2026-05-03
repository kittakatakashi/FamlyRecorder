//
//  PlayerView.swift
//  FamlyRecorder
//

import SwiftUI

struct PlayerView: View {
    let allItems: [RecordingItem]
    @ObservedObject var player: RecordingPlayer
    @State private var currentIndex: Int

    init(allItems: [RecordingItem], startIndex: Int, player: RecordingPlayer) {
        self.allItems = allItems
        self._currentIndex = State(initialValue: startIndex)
        self._player = ObservedObject(wrappedValue: player)
    }

    private var currentItem: RecordingItem { allItems[currentIndex] }
    private var hasNext: Bool { currentIndex < allItems.count - 1 }
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
        .onAppear { player.play(url: currentItem.url) }
        .onDisappear { player.stop() }
        .onChange(of: player.finishedPlayingURL) { _, finishedURL in
            guard finishedURL == currentItem.url, hasNext else { return }
            skipTo(currentIndex + 1)
        }
    }

    private func skipTo(_ index: Int) {
        guard allItems.indices.contains(index) else { return }
        currentIndex = index
        player.play(url: currentItem.url)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
