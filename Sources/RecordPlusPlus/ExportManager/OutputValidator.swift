import Foundation
import AVFoundation
import CoreMedia

struct OutputValidator {
    static func validateOutput(at url: URL) -> String {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            return "No video track found"
        }

        let formatDescriptions = track.formatDescriptions as! [CMFormatDescription]
        var result = "Codec: \(track.mediaType.rawValue)\n"
        result += "Dimensions: \(Int(track.naturalSize.width))x\(Int(track.naturalSize.height))\n"

        if let formatDesc = formatDescriptions.first {
            let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any]
            if let formatName = extensions?[kCMFormatDescriptionExtension_FormatName as String] as? String {
                result += "Format: \(formatName)\n"
            }
            let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
            let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
            result += "MediaType: \(fourCharCodeToString(mediaType))\n"
            result += "SubType: \(fourCharCodeToString(subType))\n"
        }

        return result
    }

    static func fourCharCodeToString(_ code: FourCharCode) -> String {
        let c1 = Character(UnicodeScalar((code >> 24) & 0xFF)!)
        let c2 = Character(UnicodeScalar((code >> 16) & 0xFF)!)
        let c3 = Character(UnicodeScalar((code >> 8) & 0xFF)!)
        let c4 = Character(UnicodeScalar(code & 0xFF)!)
        return "\(c1)\(c2)\(c3)\(c4)"
    }
}