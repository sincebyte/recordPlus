import Foundation
import ApplicationServices

enum AccessibilityScanner {
    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}