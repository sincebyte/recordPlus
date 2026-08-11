import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

enum StreamConfiguration {
    static func makeConfiguration(
        for window: SCWindow,
        width: Int,
        height: Int,
        frameRate: Int,
        keyColor: CGColor = CGColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
    ) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.backgroundColor = keyColor
        config.showsCursor = false
        config.capturesAudio = false
        config.scalesToFit = false
        return config
    }

    static func makeContentFilter(for window: SCWindow) -> SCContentFilter {
        SCContentFilter(desktopIndependentWindow: window)
    }
}