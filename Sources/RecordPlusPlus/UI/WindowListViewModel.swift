import Foundation
import SwiftUI
import ScreenCaptureKit
import Combine

@MainActor
final class WindowListViewModel: ObservableObject {
    @Published var applications: [(String, [WindowInfo])] = []
    @Published var selectedWindow: WindowInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let enumerator = WindowEnumerator.shared

    func refreshWindows() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let windows = try await enumerator.enumerateWindows()
            applications = await enumerator.groupByApplication(windows)
        } catch {
            errorMessage = "Failed to enumerate windows: \(error.localizedDescription)"
            Logger.shared.error("Window enumeration failed: \(error)")
        }
    }

    func selectWindow(_ window: WindowInfo) {
        selectedWindow = window
    }
}