import Foundation
import AppKit
import SwiftUI
import Combine
import CoreMedia
import CoreVideo
import CoreGraphics
import VideoToolbox
import ScreenCaptureKit

@MainActor
final class RecordingManager: ObservableObject {
    @Published var isRecording = false
    @Published var selectedWindow: WindowInfo?
    @Published var elapsedTime = "00:00:00"
    @Published var frameCount: Int64 = 0
    @Published var currentFileSize: String?
    @Published var errorMessage: String?
    @Published var keyColor: Color = Color(red: 1, green: 0, blue: 1)
    @Published var threshold: Float = 0.7
    @Published var smoothness: Float = 0.05
    @Published var spillSuppression: Float = 0.3
    @Published var selectedPreset: EncoderConfig = .hd1080p30
    @Published var cornerRadius: Float = 0
    @Published var borderColor: Color = Color(red: 0.82, green: 0.82, blue: 0.82)
    @Published var borderWidth: Float = 1

    private let captureManager = CaptureManager()
    private var frameProcessor: FrameProcessor?
    private var startTime: Date?
    private var isStopping = false
    private var timerCancellable: AnyCancellable?

    var outputURL: URL? { frameProcessor?.outputURL }

    private var borderSIMD: SIMD4<Float> {
        let nsColor = NSColor(borderColor)
        let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return SIMD4<Float>(Float(srgb.redComponent), Float(srgb.greenComponent), Float(srgb.blueComponent), Float(srgb.alphaComponent))
    }

    private var cgKeyColor: CGColor {
        let nsColor = NSColor(keyColor)
        let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return CGColor(
            srgbRed: srgb.redComponent,
            green: srgb.greenComponent,
            blue: srgb.blueComponent,
            alpha: 1.0
        )
    }

    func startRecording() {
        guard let window = selectedWindow else {
            errorMessage = "No window selected"
            return
        }
        guard !isRecording else { return }

        isRecording = true
        errorMessage = nil
        isStopping = false
        frameCount = 0
        elapsedTime = "00:00:00"

        Task {
            do {
                try await startRecordingAsync(window: window)
            } catch {
                errorMessage = "Start failed: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    private func startRecordingAsync(window: WindowInfo) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }),
              let display = content.displays.first(where: { scWindow.frame.intersects($0.frame) }) else {
            throw CaptureError.windowNotFound
        }
        let canvasW = Int(CGDisplayPixelsWide(display.displayID))
        let canvasH = Int(CGDisplayPixelsHigh(display.displayID))
        let scale = CGFloat(canvasW) / display.frame.width
        let winX = Float((scWindow.frame.origin.x - display.frame.origin.x) * scale)
        let winY = Float((scWindow.frame.origin.y - display.frame.origin.y) * scale)
        let contentW = Float(scWindow.frame.width * scale)
        let contentH = Float(scWindow.frame.height * scale)

        let generator = try AlphaGenerator()
        let config = AlphaConfig(
            keyColor: cgKeyColor,
            threshold: threshold,
            smoothness: smoothness,
            spillSuppression: spillSuppression,
            cornerRadius: cornerRadius,
            width: Float(canvasW),
            height: Float(canvasH),
            borderColor: borderSIMD,
            borderWidth: borderWidth,
            contentWidth: contentW,
            contentHeight: contentH,
            windowX: winX,
            windowY: winY
        )
        generator.updateConfig(config)

        let outputURL = ExportManager.generateOutputURL()
        let encoderConfig = EncoderConfig(width: canvasW, height: canvasH, frameRate: selectedPreset.frameRate, codec: .proRes4444)
        let enc = ProResEncoder(config: encoderConfig, outputURL: outputURL)
        try enc.startWriting()

        let processor = FrameProcessor(generator: generator, encoder: enc, frameRate: selectedPreset.frameRate)
        frameProcessor = processor

        startTime = Date()

        let fp = processor
        var transferSessionCreated = false
        var transferSession: VTPixelTransferSession?
        captureManager.onFrameReceived = { buffer in
            var pixelBuffer: CVPixelBuffer?
            pixelBuffer = CMSampleBufferGetImageBuffer(buffer)
            if pixelBuffer == nil {
                pixelBuffer = RecordingManager.createPixelBuffer(from: buffer)
            }
            guard var pixelBuffer = pixelBuffer else { return }

            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
            if format != kCVPixelFormatType_32BGRA {
                if !transferSessionCreated {
                    transferSessionCreated = true
                    VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transferSession)
                }
                if let session = transferSession {
                    var bgraBuffer: CVPixelBuffer?
                    let attrs: [String: Any] = [
                        kCVPixelBufferMetalCompatibilityKey as String: true,
                        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                    ]
                    CVPixelBufferCreate(kCFAllocatorDefault,
                        CVPixelBufferGetWidth(pixelBuffer),
                        CVPixelBufferGetHeight(pixelBuffer),
                        kCVPixelFormatType_32BGRA,
                        attrs as CFDictionary,
                        &bgraBuffer)
                    if let bgraBuffer = bgraBuffer {
                        VTPixelTransferSessionTransferImage(session, from: pixelBuffer, to: bgraBuffer)
                        pixelBuffer = bgraBuffer
                    }
                }
            }

            Task {
                do {
                    try await fp.process(pixelBuffer)
                    await MainActor.run {
                        self.frameCount += 1
                    }
                } catch {
                    Logger.shared.error("Frame: \(error.localizedDescription)")
                }
            }
        }

        try await captureManager.startCapture(
            windowID: window.windowID,
            width: canvasW,
            height: canvasH,
            frameRate: selectedPreset.frameRate,
            keyColor: cgKeyColor
        )

        Logger.shared.info("Recording started: \(outputURL.path)")

        timerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStatus()
            }
    }

    func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

        timerCancellable?.cancel()
        timerCancellable = nil

        captureManager.onFrameReceived = nil

        let outputPath = frameProcessor?.outputURL.path

        Task {
            do {
                try await captureManager.stopCapture()
            } catch {
                Logger.shared.error("Stop capture: \(error)")
            }

            do {
                try await frameProcessor?.finish()
            } catch {
                Logger.shared.error("Finish: \(error)")
            }

            updateStatus()
            frameProcessor = nil
            isRecording = false
            isStopping = false
            Logger.shared.info("Recording finished: \(outputPath ?? "unknown")")
        }
    }

    private func updateStatus() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60
        elapsedTime = String(format: "%02d:%02d:%02d", hours, minutes, seconds)

        if let url = frameProcessor?.outputURL {
            if let size = ExportManager.getFileSize(at: url) {
                currentFileSize = ExportManager.formatFileSize(size)
            }
        }
    }

    private static func createPixelBuffer(from sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let fmtDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(fmtDesc)
        let width = Int(dims.width)
        let height = Int(dims.height)

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        if let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            CVPixelBufferLockBaseAddress(pb, [])
            defer { CVPixelBufferUnlockBaseAddress(pb, []) }

            if let baseAddress = CVPixelBufferGetBaseAddress(pb) {
                let dataLength = CMBlockBufferGetDataLength(dataBuffer)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                let copyLength = min(dataLength, height * bytesPerRow)
                CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: copyLength, destination: baseAddress)
            }
        }

        return pb
    }
}