import Foundation
import Logging

/// Friendly Perfect-style logging façade over swift-log.
///
/// `LogFile` keeps the original ergonomic surface — leveled static calls that
/// return a reusable event ID — while delegating to a swift-log `Logger`. The
/// destination(s) are decided by whatever backend the application bootstraps
/// (see ``PerfectLogger/bootstrap(label:console:file:fileOptions:remoteServer:remoteToken:level:)``).
///
/// ```swift
/// PerfectLogger.bootstrap(file: "/var/log/app.log")
/// let eid = LogFile.info("server started")
/// LogFile.error("db unreachable", eventid: eid)   // correlate via the same id
/// ```
public enum LogFile {

    /// The underlying swift-log logger. Replace it to point at a custom logger,
    /// or set `logger.logLevel` to gate output without re-bootstrapping.
    nonisolated(unsafe) public static var logger = Logger(label: "perfect.logfile")

    private static func emit(_ priority: LogPriority, _ message: String, _ eventid: String) {
        logger.log(level: priority.level, "\(message)", metadata: ["eventid": .string(eventid)])
    }

    @discardableResult
    public static func debug(_ message: @autoclosure () -> String, eventid: String = UUID().uuidString) -> String {
        emit(.debug, message(), eventid); return eventid
    }

    @discardableResult
    public static func info(_ message: String, eventid: String = UUID().uuidString) -> String {
        emit(.info, message, eventid); return eventid
    }

    @discardableResult
    public static func warning(_ message: String, eventid: String = UUID().uuidString) -> String {
        emit(.warning, message, eventid); return eventid
    }

    @discardableResult
    public static func error(_ message: String, eventid: String = UUID().uuidString) -> String {
        emit(.error, message, eventid); return eventid
    }

    @discardableResult
    public static func critical(_ message: String, eventid: String = UUID().uuidString) -> String {
        emit(.critical, message, eventid); return eventid
    }

    /// Logs at `.critical` then aborts the process.
    public static func terminal(_ message: String, eventid: String = UUID().uuidString) -> Never {
        emit(.terminal, message, eventid)
        fatalError(message)
    }
}
