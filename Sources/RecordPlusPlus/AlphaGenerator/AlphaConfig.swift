import Foundation
import CoreGraphics

struct AlphaConfig: Equatable {
    var keyColor: SIMD4<Float>
    var borderColor: SIMD4<Float>
    var thresholdLow: Float
    var thresholdHigh: Float
    var spillSuppression: Float
    var cornerRadius: Float
    var width: Float
    var height: Float
    var borderWidth: Float
    var contentWidth: Float
    var contentHeight: Float

    static let `default` = AlphaConfig(
        keyColor: SIMD4<Float>(1.0, 0.0, 1.0, 1.0),
        borderColor: SIMD4<Float>(0.82, 0.82, 0.82, 1.0),
        thresholdLow: 0.0,
        thresholdHigh: 0.1,
        spillSuppression: 0.3,
        cornerRadius: 0,
        width: 1920,
        height: 1080,
        borderWidth: 0,
        contentWidth: 1920,
        contentHeight: 1080
    )

    var cgKeyColor: CGColor {
        CGColor(srgbRed: CGFloat(keyColor.x), green: CGFloat(keyColor.y), blue: CGFloat(keyColor.z), alpha: 1.0)
    }

    init(keyColor: SIMD4<Float>, borderColor: SIMD4<Float>, thresholdLow: Float, thresholdHigh: Float, spillSuppression: Float, cornerRadius: Float, width: Float, height: Float, borderWidth: Float, contentWidth: Float, contentHeight: Float) {
        self.keyColor = keyColor
        self.borderColor = borderColor
        self.thresholdLow = thresholdLow
        self.thresholdHigh = thresholdHigh
        self.spillSuppression = spillSuppression
        self.cornerRadius = cornerRadius
        self.width = width
        self.height = height
        self.borderWidth = borderWidth
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }

    init(keyColor: CGColor, threshold: Float, smoothness: Float, spillSuppression: Float = 0.3, cornerRadius: Float = 0, width: Float = 1920, height: Float = 1080, borderColor: SIMD4<Float> = SIMD4<Float>(0.82, 0.82, 0.82, 1.0), borderWidth: Float = 0, contentWidth: Float = 1920, contentHeight: Float = 1080) {
        let comps = keyColor.components ?? [1.0, 0.0, 1.0, 1.0]
        self.keyColor = SIMD4<Float>(Float(comps[0]), Float(comps[1]), Float(comps[2]), 1.0)
        self.borderColor = borderColor
        self.thresholdLow = max(0.0, threshold - smoothness)
        self.thresholdHigh = threshold + smoothness
        self.spillSuppression = spillSuppression
        self.cornerRadius = cornerRadius
        self.width = width
        self.height = height
        self.borderWidth = borderWidth
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }
}