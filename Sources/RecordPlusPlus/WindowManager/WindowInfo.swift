import Foundation
import CoreGraphics

struct WindowInfo: Identifiable, Hashable {
    let id: String
    let windowID: CGWindowID
    let appName: String
    let title: String
    let bundleID: String
    let frame: CGRect
    let isOnScreen: Bool

    var displayName: String {
        if title.isEmpty {
            return appName
        }
        return "\(appName) — \(title)"
    }
}