import Foundation
import AppKit
import SwiftUI
import Combine
import CoreMedia
import CoreVideo
import CoreGraphics
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
    @Published var threshold: Float = 0.2
    @Published var smoothness: Float = 0.15
    @Published var spillSuppression: Float = 0.3
    @Published var selectedPreset: EncoderConfig = .hd1080p30
    @Published var cornerRadius: Float = 0
    @Published var borderColor: Color = Color(red: 0.82, green: 0.82, blue: 0.82)
    @Published var borderWidth: Float = 1

    private let captureManager = CaptureManager()
    private var frameProcessor: FrameProcessor?
    private var generator: AlphaGenerator?
    private var startTime: Date?
    private var isStopping = false
    private var timerCancellable: AnyCancellable?
    private var windowUpdateTimer: AnyCancellable?
    private var windowID: CGWindowID = 0
    private var lastWindowFrame: CGRect = .zero
    private var captureDisplayID: CGDirectDisplayID = 0
    private var captureCanvasW: Int = 0
    private var captureCanvasH: Int = 0
    private var captureDisplayFrame: CGRect = .zero

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
        self.generator = generator
        self.windowID = window.windowID
        self.lastWindowFrame = scWindow.frame
        self.captureDisplayID = display.displayID
        self.captureCanvasW = canvasW
        self.captureCanvasH = canvasH
        self.captureDisplayFrame = display.frame

        startTime = Date()

        let fp = processor
        captureManager.onFrameReceived = { buffer in
            var pixelBuffer: CVPixelBuffer?
            pixelBuffer = CMSampleBufferGetImageBuffer(buffer)
            if pixelBuffer == nil {
                pixelBuffer = RecordingManager.createPixelBuffer(from: buffer)
            }
            guard let pixelBuffer = pixelBuffer else { return }

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

        windowUpdateTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateWindowFrame()
            }
    }

    func stopRecording() {
        guard !isStopping else { return }
        isStopping = true

        timerCancellable?.cancel()
        timerCancellable = nil
        windowUpdateTimer?.cancel()
        windowUpdateTimer = nil

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
            generator = nil
            isRecording = false
            isStopping = false
            captureDisplayID = 0
            captureCanvasW = 0
            captureCanvasH = 0
            captureDisplayFrame = .zero
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

    private func updateWindowFrame() {
        guard let gen = generator, windowID != 0 else { return }
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        guard let windowInfo = windowList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }),
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = boundsDict["X"] as? CGFloat,
              let y = boundsDict["Y"] as? CGFloat,
              let w = boundsDict["Width"] as? CGFloat,
              let h = boundsDict["Height"] as? CGFloat else {
            return
        }
        let newFrame = CGRect(x: x, y: y, width: w, height: h)
        guard newFrame != lastWindowFrame else { return }
        lastWindowFrame = newFrame

        let scale = CGFloat(captureCanvasW) / captureDisplayFrame.width
        let winX = Float((newFrame.origin.x - captureDisplayFrame.origin.x) * scale)
        let winY = Float((newFrame.origin.y - captureDisplayFrame.origin.y) * scale)
        let contentW = Float(newFrame.width * scale)
        let contentH = Float(newFrame.height * scale)

        let config = AlphaConfig(
            keyColor: cgKeyColor,
            threshold: threshold,
            smoothness: smoothness,
            spillSuppression: spillSuppression,
            cornerRadius: cornerRadius,
            width: Float(captureCanvasW),
            height: Float(captureCanvasH),
            borderColor: borderSIMD,
            borderWidth: borderWidth,
            contentWidth: contentW,
            contentHeight: contentH,
            windowX: winX,
            windowY: winY
        )
        gen.updateConfig(config)
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