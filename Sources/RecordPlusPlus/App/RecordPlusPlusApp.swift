import SwiftUI

fileprivate func crashSignalHandler(_ sig: Int32) {
    let name: String
    switch sig {
    case SIGABRT: name = "SIGABRT"
    case SIGSEGV: name = "SIGSEGV"
    case SIGBUS: name = "SIGBUS"
    case SIGILL: name = "SIGILL"
    case SIGFPE: name = "SIGFPE"
    case SIGTRAP: name = "SIGTRAP"
    default: name = "SIGNAL(\(sig))"
    }
    let msg = "[CRASH] Signal \(name) received"
    fputs(msg + "\n", stderr)
    fflush(stderr)
    Logger.shared.error(msg)
    exit(1)
}

@main
struct RecordPlusPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.title = "Record++"
            window.setFrameAutosaveName("RecordPlusPlusWindow")
        }
        installCrashHandlers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let msg = """
            [CRASH] Uncaught exception: \(exception.name.rawValue)
            [CRASH] Reason: \(exception.reason ?? "unknown")
            [CRASH] Call stack: \(exception.callStackSymbols.joined(separator: "\n"))
            """
            fputs(msg + "\n", stderr)
            fflush(stderr)
            Logger.shared.error(msg)
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in signals {
            signal(sig, crashSignalHandler)
        }
    }
}