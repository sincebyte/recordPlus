import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

final class ProResEncoder: @unchecked Sendable {
    private let config: EncoderConfig
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let outputURL: URL
    private var isWriting = false
    private var frameCount: Int64 = 0
    private var startTime: CMTime = .zero
    private let timeScale: CMTimeScale = 600

    init(config: EncoderConfig, outputURL: URL) {
        self.config = config
        self.outputURL = outputURL
    }

    func startWriting() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: config.avCodecType,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let sourcePixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: config.pixelFormat,
            kCVPixelBufferWidthKey as String: config.width,
            kCVPixelBufferHeightKey as String: config.height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelAttributes
        )

        guard writer.canAdd(input) else {
            throw CaptureError.encoderCreationFailed("Cannot add video input to asset writer")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw CaptureError.encoderCreationFailed(
                writer.error?.localizedDescription ?? "Unknown error"
            )
        }

        writer.startSession(atSourceTime: .zero)

        assetWriter = writer
        assetWriterInput = input
        pixelBufferAdaptor = adaptor
        isWriting = true
        frameCount = 0
        startTime = CMTime.zero
    }

    func appendPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) throws {
        guard let writer = assetWriter, let input = assetWriterInput, isWriting else {
            throw CaptureError.encoderNotReady
        }

        guard writer.status == .writing else {
            throw CaptureError.encoderWriteFailed(
                "Writer status: \(writer.status.rawValue), error: \(writer.error?.localizedDescription ?? "none")"
            )
        }

        guard input.isReadyForMoreMediaData else {
            throw CaptureError.encoderNotReady
        }

        guard let adaptor = pixelBufferAdaptor else {
            throw CaptureError.encoderNotReady
        }

        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            throw CaptureError.encoderWriteFailed(
                writer.error?.localizedDescription ?? "Unknown append error"
            )
        }
        frameCount += 1
    }

    func finishWriting() async throws {
        guard let writer = assetWriter, isWriting else { return }
        isWriting = false

        let status = writer.status
        if status == .failed || status == .cancelled {
            assetWriter = nil
            assetWriterInput = nil
            pixelBufferAdaptor = nil
            return
        }

        if status == .writing || status == .unknown {
            assetWriterInput?.markAsFinished()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        if writer.status == .failed {
            Logger.shared.error("Writer failed: \(writer.error?.localizedDescription ?? "unknown")")
        }

        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
    }

    var currentFrameCount: Int64 { frameCount }
    var outputFileURL: URL { outputURL }
}