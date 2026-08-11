import Foundation
import CoreMedia
import CoreVideo

actor FrameProcessor {
    private let generator: AlphaGenerator
    private let encoder: ProResEncoder
    private var nextFramePts: CMTime = .zero
    private let frameRate: Int
    private var isStopped = false

    init(generator: AlphaGenerator, encoder: ProResEncoder, frameRate: Int) {
        self.generator = generator
        self.encoder = encoder
        self.frameRate = frameRate
    }

    func process(_ pixelBuffer: CVPixelBuffer) throws {
        guard !isStopped else { return }

        let processed = try generator.processPixelBuffer(pixelBuffer)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        let pts = nextFramePts
        nextFramePts = CMTimeAdd(nextFramePts, frameDuration)

        try encoder.appendPixelBuffer(processed, presentationTime: pts)
    }

    func finish() async throws {
        isStopped = true
        try await encoder.finishWriting()
    }

    nonisolated var outputURL: URL { encoder.outputFileURL }
}