import Foundation
import CoreVideo

final class PixelBufferPool: @unchecked Sendable {
    private var pool: CVPixelBufferPool?
    private let width: Int
    private let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    func createPool() throws {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &newPool)
        guard status == kCVReturnSuccess, let pool = newPool else {
            throw CaptureError.encoderCreationFailed("Failed to create pixel buffer pool")
        }
        self.pool = pool
    }

    func createPixelBuffer() throws -> CVPixelBuffer {
        guard let pool else { throw CaptureError.encoderNotReady }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw CaptureError.invalidPixelBuffer
        }
        return buffer
    }
}