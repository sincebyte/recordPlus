import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics

final class CaptureManager: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var streamDelegate: StreamDelegate?
    private var activeWindow: SCWindow?
    private var isCapturing = false
    private let captureQueue = DispatchQueue(label: "com.recordplusplus.capture", qos: .userInitiated)

    var onFrameReceived: ((CMSampleBuffer) -> Void)?

    override init() {
        super.init()
    }

    func startCapture(
        windowID: CGWindowID,
        width: Int,
        height: Int,
        frameRate: Int,
        keyColor: CGColor = CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
    ) async throws {
        guard !isCapturing else { throw CaptureError.streamAlreadyRunning }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        activeWindow = window

        let config = StreamConfiguration.makeConfiguration(
            for: window,
            width: width,
            height: height,
            frameRate: frameRate,
            keyColor: keyColor
        )
        let filter = StreamConfiguration.makeContentFilter(for: window)

        let delegate = StreamDelegate()
        let output = StreamOutput()
        let newStream = SCStream(filter: filter, configuration: config, delegate: delegate)

        try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        stream = newStream
        streamOutput = output
        streamDelegate = delegate

        output.onFrameReceived = { [weak self] buffer in
            self?.onFrameReceived?(buffer)
        }

        try await newStream.startCapture()
        isCapturing = true
    }

    func stopCapture() async throws {
        guard isCapturing, let stream else { throw CaptureError.streamNotRunning }
        isCapturing = false
        do {
            try await stream.stopCapture()
        } catch {
            Logger.shared.error("Stream stop error: \(error)")
        }
        self.stream = nil
        streamOutput = nil
        streamDelegate = nil
        activeWindow = nil
    }

    var capturing: Bool { isCapturing }
}

private final class StreamDelegate: NSObject, SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Logger.shared.error("Stream stopped with error: \(error.localizedDescription)")
    }
}

private final class StreamOutput: NSObject, SCStreamOutput {
    var onFrameReceived: ((CMSampleBuffer) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        onFrameReceived?(sampleBuffer)
    }
}