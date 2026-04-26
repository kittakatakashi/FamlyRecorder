//
//  SpeechActivityDetector.swift
//  FamlyRecorder
//

import AVFoundation
import SoundAnalysis

final class SpeechActivityDetector: NSObject {
    private var analyzer: SNAudioStreamAnalyzer?
    private var framePosition: AVAudioFramePosition = 0
    private(set) var speechConfidence: Float = 0

    func prepare(format: AVAudioFormat) throws {
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.overlapFactor = 0.9
        try analyzer.add(request, withObserver: self)
        self.analyzer = analyzer
    }

    func analyze(_ buffer: AVAudioPCMBuffer) {
        analyzer?.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
    }
}

extension SpeechActivityDetector: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        speechConfidence = Float(result.classification(forIdentifier: "speech")?.confidence ?? 0)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        speechConfidence = 0
    }
}
