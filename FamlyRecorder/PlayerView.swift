//
//  PlayerView.swift
//  FamlyRecorder
//

import SwiftUI

struct PlayerView: View {
    let item: RecordingItem
    @ObservedObject var player: RecordingPlayer

    private var isPlaying: Bool { player.playingURL == item.url && player.isPlaying }
    private var isLoaded: Bool  { player.playingURL == item.url }
    private var currentTime: TimeInterval { isLoaded ? player.currentTime : 0 }
    private var totalDuration: TimeInterval { isLoaded ? player.duration : item.duration }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text(item.date, format: .dateTime.year().month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(item.date, format: .dateTime.hour().minute())
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

            HStack(spacing: 56) {
                Button {
                    player.seek(to: max(0, currentTime - 15))
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                }
                .tint(.primary)

                Button {
                    player.toggle(url: item.url)
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 80))
                }
                .tint(.orange)

                Button {
                    player.seek(to: min(totalDuration, currentTime + 15))
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title)
                }
                .tint(.primary)
            }

            Spacer()
        }
        .navigationTitle("録音再生")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player.play(url: item.url) }
        .onDisappear { player.stop() }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
