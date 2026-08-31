// AFLog.swift
// AdaptyFlowKit SDK
//
// Module-wide logging.

import Foundation

// MARK: - AFLogLevel

/// Severity of a log record emitted by AdaptyFlowKit.
public enum AFLogLevel: Int, Sendable, Comparable, CustomStringConvertible {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    /// Emits nothing. Assign to `AdaptyFlowKit.logLevel` to silence the SDK.
    case off = 4

    public static func < (lhs: AFLogLevel, rhs: AFLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .warning: "warning"
        case .error: "error"
        case .off: "off"
        }
    }
}

// MARK: - Configuration

public extension AdaptyFlowKit {

    /// Minimum severity that reaches `logHandler`.
    ///
    /// Defaults to `.debug` in DEBUG builds and `.warning` in release builds, so a
    /// shipped app only sees problems instead of flow tracing. Assign `.off` to
    /// silence the SDK entirely.
    static var logLevel: AFLogLevel = {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }()

    /// Destination for log records. `nil` (the default) prints to the console.
    ///
    /// Assign to route SDK logs into OSLog, Firebase, or your own logger:
    /// ```swift
    /// AdaptyFlowKit.logHandler = { level, message in
    ///     MyLogger.log("[AdaptyFlowKit][\(level)] \(message)")
    /// }
    /// ```
    static var logHandler: (@Sendable (AFLogLevel, String) -> Void)?
}

// MARK: - AFLog

/// Internal entry point for SDK logging.
///
/// Messages are built lazily, so a record filtered out by `AdaptyFlowKit.logLevel`
/// costs nothing beyond one integer comparison — string interpolation at the call
/// site is never evaluated.
enum AFLog {

    static func debug(_ message: @autoclosure () -> String) { emit(.debug, message) }
    static func info(_ message: @autoclosure () -> String) { emit(.info, message) }
    static func warning(_ message: @autoclosure () -> String) { emit(.warning, message) }
    static func error(_ message: @autoclosure () -> String) { emit(.error, message) }

    private static func emit(_ level: AFLogLevel, _ message: () -> String) {
        // `.off` is above every real level, so this single check also handles silencing.
        guard level >= AdaptyFlowKit.logLevel else { return }
        let text = message()

        if let handler = AdaptyFlowKit.logHandler {
            handler(level, text)
        } else {
            print("[AdaptyFlowKit][\(level)] \(text)")
        }
    }
}
