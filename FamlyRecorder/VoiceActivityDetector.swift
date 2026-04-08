//
//  VoiceActivityDetector.swift
//  FamlyRecorder
//
//  Created by Codex on 2026/04/08.
//

@preconcurrency import AVFoundation
import Foundation

struct VoiceActivityDetector {
    private(set) var noiseFloorDB: Float = -60
    private(set) var smoothedDB: Float = -60

    private let minDB: Float = -90
    private let maxDB: Float = 0
    private let smoothingFactor: Float = 0.2
    private let noiseLearningRate: Float = 0.06

    mutating func score(for buffer: AVAudioPCMBuffer) -> Float {
        guard let db = averageDecibelLevel(in: buffer) else { return 0 }
        return score(forDecibel: db)
    }

    mutating func score(forDecibel db: Float) -> Float {
        let clamped = min(max(db, minDB), maxDB)
        smoothedDB = (1 - smoothingFactor) * smoothedDB + smoothingFactor * clamped

        let likelyNoise = smoothedDB <= noiseFloorDB + 6
        if likelyNoise {
            noiseFloorDB = (1 - noiseLearningRate) * noiseFloorDB + noiseLearningRate * smoothedDB
        }

        let normalized = (smoothedDB - (noiseFloorDB + 4)) / 18
        return min(max(normalized, 0), 1)
    }

    private func averageDecibelLevel(in buffer: AVAudioPCMBuffer) -> Float? {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return nil }

        var sum: Float = 0

        if let channelData = buffer.floatChannelData {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let value = samples[frame]
                    sum += value * value
                }
            }
        } else if let channelData = buffer.int16ChannelData {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let normalized = Float(samples[frame]) / Float(Int16.max)
                    sum += normalized * normalized
                }
            }
        } else if let channelData = buffer.int32ChannelData {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let normalized = Float(samples[frame]) / Float(Int32.max)
                    sum += normalized * normalized
                }
            }
        } else {
            return nil
        }

        let sampleCount = max(1, frameCount * channelCount)
        let rms = sqrt(sum / Float(sampleCount))
        let clampedRMS = max(rms, 0.000_000_1)
        return 20 * log10(clampedRMS)
    }
}
