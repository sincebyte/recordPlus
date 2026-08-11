import Foundation
import CoreGraphics

struct AlphaConfig: Equatable {
    var keyColor: SIMD4<Float>
    var thresholdLow: Float
    var thresholdHigh: Float
    var spillSuppression: Float

    static let `default` = AlphaConfig(
        keyColor: SIMD4<Float>(1.0, 0.0, 1.0, 1.0),
        thresholdLow: 0.0,
        thresholdHigh: 0.1,
        spillSuppression: 0.3
    )

    var cgKeyColor: CGColor {
        CGColor(srgbRed: CGFloat(keyColor.x), green: CGFloat(keyColor.y), blue: CGFloat(keyColor.z), alpha: 1.0)
    }

    init(keyColor: SIMD4<Float>, thresholdLow: Float, thresholdHigh: Float, spillSuppression: Float) {
        self.keyColor = keyColor
        self.thresholdLow = thresholdLow
        self.thresholdHigh = thresholdHigh
        self.spillSuppression = spillSuppression
    }

    init(keyColor: CGColor, threshold: Float, smoothness: Float, spillSuppression: Float = 0.3) {
        let comps = keyColor.components ?? [1.0, 0.0, 1.0, 1.0]
        self.keyColor = SIMD4<Float>(Float(comps[0]), Float(comps[1]), Float(comps[2]), 1.0)
        self.thresholdLow = max(0.0, threshold - smoothness)
        self.thresholdHigh = threshold + smoothness
        self.spillSuppression = spillSuppression
    }
}