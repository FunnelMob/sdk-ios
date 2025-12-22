import Foundation
import os.log

/// Internal logger for FunnelMob SDK
enum Logger {

    static var logLevel: FunnelMobConfiguration.LogLevel = .none

    private static let subsystem = "com.funnelmob.sdk"
    private static let osLog = OSLog(subsystem: subsystem, category: "FunnelMob")

    static func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    static func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warning, file: file, line: line)
    }

    static func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    static func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    static func verbose(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .verbose, file: file, line: line)
    }

    private static func log(
        _ message: String,
        level: FunnelMobConfiguration.LogLevel,
        file: String,
        line: Int
    ) {
        guard level <= logLevel else { return }

        let filename = (file as NSString).lastPathComponent
        let prefix = levelPrefix(level)
        let formatted = "[\(prefix)] [\(filename):\(line)] \(message)"

        #if DEBUG
        print("[FunnelMob] \(formatted)")
        #endif

        os_log("%{public}@", log: osLog, type: osLogType(level), formatted)
    }

    private static func levelPrefix(_ level: FunnelMobConfiguration.LogLevel) -> String {
        switch level {
        case .none: return ""
        case .error: return "ERROR"
        case .warning: return "WARN"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .verbose: return "VERBOSE"
        }
    }

    private static func osLogType(_ level: FunnelMobConfiguration.LogLevel) -> OSLogType {
        switch level {
        case .none: return .default
        case .error: return .error
        case .warning: return .default
        case .info: return .info
        case .debug: return .debug
        case .verbose: return .debug
        }
    }
}
