import Foundation
import CoreMedia
import CoreVideo

actor FrameProcessor {
    private let generator: AlphaGenerator
    private let encoder: ProResEncoder
    private var nextFramePts: CMTime = .zero
    private let frameRate: Int
    private let canvasWidth: Int
    private let canvasHeight: Int
    private var isStopped = false
    private var blankPixelBufferPool: CVPixelBufferPool?

    init(generator: AlphaGenerator, encoder: ProResEncoder, frameRate: Int, canvasWidth: Int, canvasHeight: Int) {
        self.generator = generator
        self.encoder = encoder
        self.frameRate = frameRate
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    func process(_ pixelBuffer: CVPixelBuffer) throws {
        guard !isStopped else { return }

        let processed = try generator.processPixelBuffer(pixelBuffer)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        let pts = nextFramePts
        nextFramePts = CMTimeAdd(nextFramePts, frameDuration)

        try encoder.appendPixelBuffer(processed, presentationTime: pts)
    }

    func processBlank() throws {
        guard !isStopped else { return }

        let blank = try createBlankPixelBuffer()

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        let pts = nextFramePts
        nextFramePts = CMTimeAdd(nextFramePts, frameDuration)

        try encoder.appendPixelBuffer(blank, presentationTime: pts)
    }

    private func createBlankPixelBuffer() throws -> CVPixelBuffer {
        if blankPixelBufferPool == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: canvasWidth,
                kCVPixelBufferHeightKey as String: canvasHeight,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var pool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
            guard status == kCVReturnSuccess, let p = pool else {
                throw CaptureError.invalidPixelBuffer
            }
            blankPixelBufferPool = p
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, blankPixelBufferPool!, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw CaptureError.invalidPixelBuffer
        }

        CVPixelBufferLockBaseAddress(pb, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pb) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            memset(baseAddress, 0, bytesPerRow * canvasHeight)
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        return pb
    }

    func finish() async throws {
        isStopped = true
        blankPixelBufferPool = nil
        try await encoder.finishWriting()
    }

    nonisolated var outputURL: URL { encoder.outputFileURL }
}