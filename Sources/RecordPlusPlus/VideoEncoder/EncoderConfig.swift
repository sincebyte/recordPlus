import Foundation
import AVFoundation
import CoreVideo

struct EncoderConfig: Sendable, Hashable {
    var width: Int
    var height: Int
    var frameRate: Int
    var codec: CodecType

    enum CodecType: Sendable {
        case proRes4444
        case proRes422
        case hevcAlpha
    }

    static let hd1080p30 = EncoderConfig(width: 1920, height: 1080, frameRate: 30, codec: .proRes4444)
    static let qhd1440p30 = EncoderConfig(width: 2560, height: 1440, frameRate: 30, codec: .proRes4444)
    static let uhd2160p30 = EncoderConfig(width: 3840, height: 2160, frameRate: 30, codec: .proRes4444)

    static let hd1080p60 = EncoderConfig(width: 1920, height: 1080, frameRate: 60, codec: .proRes4444)
    static let qhd1440p60 = EncoderConfig(width: 2560, height: 1440, frameRate: 60, codec: .proRes4444)
    static let uhd2160p60 = EncoderConfig(width: 3840, height: 2160, frameRate: 60, codec: .proRes4444)

    var avCodecType: AVVideoCodecType {
        switch codec {
        case .proRes4444, .proRes422:
            return AVVideoCodecType(rawValue: "ap4h")
        case .hevcAlpha:
            if #available(macOS 11.0, *) {
                return .hevc
            }
            return AVVideoCodecType(rawValue: "ap4h")
        }
    }

    var pixelFormat: OSType {
        kCVPixelFormatType_32BGRA
    }

    var displayName: String {
        "\(width)x\(height) @ \(frameRate)fps"
    }
}