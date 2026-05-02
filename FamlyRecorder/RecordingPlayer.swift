//
//  RecordingPlayer.swift
//  FamlyRecorder
//

import AVFoundation
import Combine

@MainActor
final class RecordingPlayer: NSObject, ObservableObject {
    @Published private(set) var playingURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timerCancellable: AnyCancellable?

    func toggle(url: URL) {
        if playingURL == url && isPlaying {
            pause()
        } else {
            play(url: url)
        }
    }

    func play(url: URL) {
        stop()
        do {
            // RecorderManager が playAndRecord セッションを保持しているためカテゴリは変更しない
            // overrideOutputAudioPort でスピーカー出力に切り替えるだけで再生できる
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            playingURL = url
            isPlaying = true
            duration = p.duration
            startTimer()
        } catch {
            // 再生失敗はサイレントに無視（UIで isPlaying == false として表示される）
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playingURL = nil
        currentTime = 0
        duration = 0
        stopTimer()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.currentTime = self?.player?.currentTime ?? 0
            }
    }

    private func stopTimer() {
        timerCancellable = nil
    }
}

extension RecordingPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
