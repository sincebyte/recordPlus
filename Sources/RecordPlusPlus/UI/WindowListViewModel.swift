import Foundation
import SwiftUI
import ScreenCaptureKit
import Combine

@MainActor
final class WindowListViewModel: ObservableObject {
    @Published var applications: [(String, [WindowInfo])] = []
    @Published var selectedWindow: WindowInfo?
    @Published var errorMessage: String?

    private let enumerator = WindowEnumerator.shared
    private var autoRefreshTask: Task<Void, Never>?

    func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                await refreshWindows()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refreshWindows() async {
        errorMessage = nil

        do {
            let windows = try await enumerator.enumerateWindows()
            let previousSelection = selectedWindow
            applications = await enumerator.groupByApplication(windows)
            if let prev = previousSelection, let stillExists = windows.first(where: { $0.id == prev.id }) {
                selectedWindow = stillExists
            } else if previousSelection != nil {
                selectedWindow = nil
            }
        } catch {
            errorMessage = "Failed to enumerate windows: \(error.localizedDescription)"
            Logger.shared.error("Window enumeration failed: \(error)")
        }
    }

    func selectWindow(_ window: WindowInfo) {
        selectedWindow = window
    }
}