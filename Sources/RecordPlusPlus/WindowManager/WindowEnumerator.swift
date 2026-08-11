import Foundation
import ScreenCaptureKit
import CoreGraphics

actor WindowEnumerator {
    static let shared = WindowEnumerator()

    private init() {}

    func enumerateWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let windows = content.windows
        let apps = content.applications

        let appMap = Dictionary(uniqueKeysWithValues: apps.map { ($0.processID, $0) })

        var result: [WindowInfo] = []
        var seen = Set<String>()

        for window in windows {
            guard let app = appMap[window.owningApplication?.processID ?? 0] else { continue }
            guard shouldInclude(app: app, window: window) else { continue }

            let windowID = window.windowID
            let title = window.title ?? ""
            let appName = app.applicationName

            let id = "\(app.bundleIdentifier)-\(windowID)"
            if seen.contains(id) { continue }
            seen.insert(id)

            let frame = window.frame

            let info = WindowInfo(
                id: id,
                windowID: windowID,
                appName: appName,
                title: title,
                bundleID: app.bundleIdentifier,
                frame: frame,
                isOnScreen: window.isOnScreen
            )
            result.append(info)
        }

        result.sort { a, b in
            if a.isOnScreen != b.isOnScreen { return a.isOnScreen }
            if a.appName != b.appName { return a.appName < b.appName }
            return a.title < b.title
        }

        return result
    }

    private func shouldInclude(app: SCRunningApplication, window: SCWindow) -> Bool {
        let excluded: Set<String> = [
            "com.apple.dock",
            "com.apple.WindowManager",
            "com.apple.systempreferences",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui"
        ]
        if excluded.contains(app.bundleIdentifier) {
            return false
        }

        let frame = window.frame
        if frame.width < 50 || frame.height < 50 { return false }
        if frame.width < 200 && frame.height < 200 && !window.isOnScreen { return false }

        return true
    }

    func groupByApplication(_ windows: [WindowInfo]) -> [(String, [WindowInfo])] {
        let grouped = Dictionary(grouping: windows) { $0.appName }
        return grouped.sorted { $0.key < $1.key }
    }
}