import Foundation
import OSLog

final class Logger {
    static let shared = Logger()
    private let logger: OSLog

    private init() {
        logger = OSLog(subsystem: "com.recordplusplus.app", category: "record++")
    }

    func info(_ message: String) {
        os_log(.info, log: logger, "%{public}@", message)
    }

    func error(_ message: String) {
        os_log(.error, log: logger, "%{public}@", message)
    }

    func debug(_ message: String) {
        os_log(.debug, log: logger, "%{public}@", message)
    }
}