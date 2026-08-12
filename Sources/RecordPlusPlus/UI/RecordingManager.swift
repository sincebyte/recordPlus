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
    @Published var isWindowVisible = true

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
    private var borderRestoreWorkItem: DispatchWorkItem?
    private var blankFrameTimer: AnyCancellable?
    private var lastFrameWrittenTime: Date = .distantPast

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
        isWindowVisible = true

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

        let processor = FrameProcessor(generator: generator, encoder: enc, frameRate: selectedPreset.frameRate, canvasWidth: canvasW, canvasHeight: canvasH)
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
        captureManager.onFrameReceived = { [weak self] buffer in
            guard let self else { return }
            var pixelBuffer: CVPixelBuffer?
            pixelBuffer = CMSampleBufferGetImageBuffer(buffer)
            if pixelBuffer == nil {
                pixelBuffer = RecordingManager.createPixelBuffer(from: buffer)
            }
            guard let pixelBuffer = pixelBuffer else { return }

            let visible = self.isWindowVisible
            Task {
                do {
                    if visible {
                        try await fp.process(pixelBuffer)
                    } else {
                        _ = pixelBuffer
                        try await fp.processBlank()
                    }
                    await MainActor.run {
                        self.frameCount += 1
                        self.lastFrameWrittenTime = Date()
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

        windowUpdateTimer = Timer.publish(every: 0.05, on: .main, in: .common)
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
        borderRestoreWorkItem?.cancel()
        borderRestoreWorkItem = nil
        blankFrameTimer?.cancel()
        blankFrameTimer = nil

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

        let onScreenList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreenWindow = onScreenList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID })

        if let windowInfo = onScreenWindow {
            if !isWindowVisible {
                isWindowVisible = true
                stopBlankFrameFallback()
                Logger.shared.info("Window \(windowID) appeared — visible")
            }

            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat else {
                return
            }
            let newFrame = CGRect(x: x, y: y, width: w, height: h)
            guard newFrame != lastWindowFrame else { return }

            let isGrowing = newFrame.width > lastWindowFrame.width || newFrame.height > lastWindowFrame.height
            lastWindowFrame = newFrame

            let scale = CGFloat(captureCanvasW) / captureDisplayFrame.width
            let winX = Float((newFrame.origin.x - captureDisplayFrame.origin.x) * scale)
            let winY = Float((newFrame.origin.y - captureDisplayFrame.origin.y) * scale)
            let contentW = Float(newFrame.width * scale)
            let contentH = Float(newFrame.height * scale)

            borderRestoreWorkItem?.cancel()

            if isGrowing {
                let config = AlphaConfig(
                    keyColor: cgKeyColor,
                    threshold: threshold,
                    smoothness: smoothness,
                    spillSuppression: spillSuppression,
                    cornerRadius: cornerRadius,
                    width: Float(captureCanvasW),
                    height: Float(captureCanvasH),
                    borderColor: borderSIMD,
                    borderWidth: 0,
                    contentWidth: contentW,
                    contentHeight: contentH,
                    windowX: winX,
                    windowY: winY
                )
                gen.updateConfig(config)

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, let gen = self.generator, self.windowID != 0 else { return }
                    let restoreConfig = AlphaConfig(
                        keyColor: self.cgKeyColor,
                        threshold: self.threshold,
                        smoothness: self.smoothness,
                        spillSuppression: self.spillSuppression,
                        cornerRadius: self.cornerRadius,
                        width: Float(self.captureCanvasW),
                        height: Float(self.captureCanvasH),
                        borderColor: self.borderSIMD,
                        borderWidth: self.borderWidth,
                        contentWidth: contentW,
                        contentHeight: contentH,
                        windowX: winX,
                        windowY: winY
                    )
                    gen.updateConfig(restoreConfig)
                }
                borderRestoreWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
            } else {
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
        } else {
            let allList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let existingWindow = allList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID })

            if existingWindow != nil {
                if isWindowVisible {
                    isWindowVisible = false
                    startBlankFrameFallback()
                    Logger.shared.info("Window \(windowID) hidden — writing blank frames")
                }
            } else {
                if isWindowVisible {
                    isWindowVisible = false
                    startBlankFrameFallback()
                    Logger.shared.info("Window \(windowID) disappeared from window list")
                }
            }
        }
    }

    private func startBlankFrameFallback() {
        guard blankFrameTimer == nil, frameProcessor != nil else { return }
        let interval = 1.0 / Double(selectedPreset.frameRate)
        blankFrameTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let fp = self.frameProcessor, !self.isWindowVisible else { return }
                let elapsed = Date().timeIntervalSince(self.lastFrameWrittenTime)
                guard elapsed >= interval else { return }

                Task {
                    do {
                        try await fp.processBlank()
                        await MainActor.run {
                            self.frameCount += 1
                            self.lastFrameWrittenTime = Date()
                        }
                    } catch {
                        Logger.shared.error("Blank fallback: \(error.localizedDescription)")
                    }
                }
            }
    }

    private func stopBlankFrameFallback() {
        blankFrameTimer?.cancel()
        blankFrameTimer = nil
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