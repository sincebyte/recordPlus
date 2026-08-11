import Foundation

enum CaptureError: Error, LocalizedError {
    case noStreamAvailable
    case permissionDenied
    case encoderCreationFailed(String)
    case encoderNotReady
    case encoderWriteFailed(String)
    case invalidPixelBuffer
    case metalDeviceNotFound
    case metalCommandQueueCreationFailed
    case metalShaderNotFound
    case metalComputePipelineCreationFailed(String)
    case windowNotFound
    case streamAlreadyRunning
    case streamNotRunning
    case invalidConfiguration(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noStreamAvailable:
            return "No stream available for the selected window."
        case .permissionDenied:
            return "Screen recording permission is required. Please grant permission in System Settings > Privacy & Security > Screen Recording."
        case .encoderCreationFailed(let reason):
            return "Failed to create encoder: \(reason)"
        case .encoderNotReady:
            return "Encoder is not ready to accept frames."
        case .encoderWriteFailed(let reason):
            return "Failed to write frame: \(reason)"
        case .invalidPixelBuffer:
            return "Invalid pixel buffer provided."
        case .metalDeviceNotFound:
            return "Metal device not found on this system."
        case .metalCommandQueueCreationFailed:
            return "Failed to create Metal command queue."
        case .metalShaderNotFound:
            return "Chroma Key Metal shader not found."
        case .metalComputePipelineCreationFailed(let reason):
            return "Failed to create compute pipeline: \(reason)"
        case .windowNotFound:
            return "Target window not found."
        case .streamAlreadyRunning:
            return "Capture stream is already running."
        case .streamNotRunning:
            return "Capture stream is not running."
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}