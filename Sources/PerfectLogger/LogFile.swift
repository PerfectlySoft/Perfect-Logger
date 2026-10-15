import Foundation
import Logging

/// Friendly Perfect-style logging façade over swift-log.
///
/// `LogFile` keeps the original ergonomic surface — leveled static calls that
/// return a reusable event ID — while delegating to a swift-log `Logger`. The
/// destination(s) are decided by whatever backend the application bootstraps
/// (see ``PerfectLogger/bootstrap(console:file:fileOptions:remoteServer:remoteToken:level:metadataProvider:)``).
///
/// ```swift
/// PerfectLogger.bootstrap(file: "/var/log/app.log")
/// let eid = LogFile.info("server started")
/// LogFile.error("db unreachable", eventid: eid)   // correlate via the same id
/// ```
public enum LogFile {

    /// The underlying swift-log logger. Replace it to point at a custom logger,
    /// or set `logger.logLevel` to gate output without re-bootstrapping.
    ///
    /// Reads and writes are thread-safe. Until it is assigned, this is a logger
    /// labelled `perfect.logfile` from the current `LoggingSystem` backend, and
    /// ``PerfectLogger/bootstrap(console:file:fileOptions:remoteServer:remoteToken:level:metadataProvider:)``
    /// rebinds it to the new backend even if `LogFile` was used before bootstrapping.
    public static var logger: Logger {
        get {
            storage.lock.lock()
            defer { storage.lock.unlock() }
            if let logger = storage.logger { return logger }
            let logger = Logger(label: defaultLabel)
            storage.logger = logger
            return logger
        }
        set {
            storage.lock.lock()
            defer { storage.lock.unlock() }
            storage.logger = newValue
            storage.assigned = true
        }
    }

    private static let defaultLabel = "perfect.logfile"

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var logger: Logger?
        var assigned = false
    }

    private static let storage = Storage()

    /// Drops the default logger so the next use picks up the current backend.
    /// A logger assigned through ``logger`` is kept.
    static func rebindDefaultLogger() {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        if !storage.assigned { storage.logger = nil }
    }

    private static func emit(_ priority: LogPriority, _ message: @autoclosure () -> String, _ eventid: String) {
        var metadata: Logger.Metadata = ["eventid": .string(eventid)]
        if priority == .terminal { metadata[LogPriority.metadataKey] = "terminal" }
        logger.log(level: priority.level, "\(message())", metadata: metadata)
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
    ///
    /// The event carries `priority=terminal` metadata, which ``FileLogHandler``
    /// writes as `[EMERG]`. File and console output are written synchronously
    /// before the abort; a ``RemoteLogHandler`` will normally not get the event out.
    public static func terminal(_ message: String, eventid: String = UUID().uuidString) -> Never {
        emit(.terminal, message, eventid)
        fatalError(message)
    }
}
