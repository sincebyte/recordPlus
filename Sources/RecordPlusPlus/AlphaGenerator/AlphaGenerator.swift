import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreMedia
import IOSurface
import os

final class AlphaGenerator: @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let threadgroupSize: MTLSize
    private var _config = AlphaConfig.default
    private var configLock = os_unfair_lock()
    private var outputPool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0

    private var config: AlphaConfig {
        get {
            os_unfair_lock_lock(&configLock)
            defer { os_unfair_lock_unlock(&configLock) }
            return _config
        }
        set {
            os_unfair_lock_lock(&configLock)
            _config = newValue
            os_unfair_lock_unlock(&configLock)
        }
    }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CaptureError.metalDeviceNotFound
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw CaptureError.metalCommandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "chromaKeyKernel") else {
            throw CaptureError.metalShaderNotFound
        }

        do {
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            throw CaptureError.metalComputePipelineCreationFailed(error.localizedDescription)
        }

        threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
    }

    func updateConfig(_ newConfig: AlphaConfig) {
        config = newConfig
    }

    func processPixelBuffer(_ pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let outBuffer = try createOutputPixelBuffer(width: width, height: height)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(outBuffer, [])

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(outBuffer, [])
        }

        let inTexture = try makeTexture(from: pixelBuffer, width: width, height: height)
        let outTexture = try makeTexture(from: outBuffer, width: width, height: height)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw CaptureError.encoderCreationFailed("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inTexture, index: 0)
        encoder.setTexture(outTexture, index: 1)

        var metalConfig = config
        encoder.setBytes(&metalConfig, length: MemoryLayout<AlphaConfig>.stride, index: 0)

        let gridSize = MTLSize(width: width, height: height, depth: 1)
        let threadsPerGroup = MTLSize(
            width: min(threadgroupSize.width, pipelineState.threadExecutionWidth),
            height: min(threadgroupSize.height, pipelineState.maxTotalThreadsPerThreadgroup / pipelineState.threadExecutionWidth),
            depth: 1
        )
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return outBuffer
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared

        if let iosurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            guard let texture = device.makeTexture(descriptor: desc, iosurface: iosurface, plane: 0) else {
                throw CaptureError.invalidPixelBuffer
            }
            return texture
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CaptureError.invalidPixelBuffer
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let texture = device.makeTexture(descriptor: desc) else {
            throw CaptureError.invalidPixelBuffer
        }
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: bytesPerRow)
        return texture
    }

    private func createOutputPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        if let pool = outputPool, width == poolWidth && height == poolHeight {
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                throw CaptureError.invalidPixelBuffer
            }
            return buffer
        }

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
            throw CaptureError.invalidPixelBuffer
        }
        outputPool = pool
        poolWidth = width
        poolHeight = height

        var pixelBuffer: CVPixelBuffer?
        let createStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard createStatus == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw CaptureError.invalidPixelBuffer
        }
        return buffer
    }
}