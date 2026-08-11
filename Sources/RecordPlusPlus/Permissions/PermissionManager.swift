import Foundation
import ScreenCaptureKit

@MainActor
final class PermissionManager: ObservableObject {
    @Published var screenRecordingGranted = false

    func checkPermissions() async {
        let granted = await canRecordScreen()
        screenRecordingGranted = granted
    }

    func requestScreenRecordingPermission() async {
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        screenRecordingGranted = content != nil
    }

    private func canRecordScreen() async -> Bool {
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content != nil
    }

    var allPermissionsGranted: Bool {
        screenRecordingGranted
    }
}