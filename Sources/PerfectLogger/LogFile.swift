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
    /// Each read and each write is thread-safe, but a mutation through the
    /// property, such as `LogFile.logger.logLevel = .debug`, is a separate read and
    /// write: run concurrently with `LogFile.logger = other`, one of them can be lost.
    ///
    /// Until it is assigned, this is a logger labelled `perfect.logfile` from the
    /// current `LoggingSystem` backend.
    /// ``PerfectLogger/bootstrap(console:file:fileOptions:remoteServer:remoteToken:level:metadataProvider:)``
    /// rebinds it to the new backend, so `LogFile` can be used before bootstrapping.
    /// If it was modified in place before bootstrapping (for example its
    /// `logLevel`), bootstrap rebuilds it from the new backend with the same
    /// `logLevel` and metadata. A logger with any other label that you assign is kept.
    public static var logger: Logger {
        get {
            storage.lock.lock()
            if let logger = storage.logger {
                storage.lock.unlock()
                return logger
            }
            let generation = storage.generation
            storage.lock.unlock()

            // Logger(label:) runs the LoggingSystem factory, which is user code
            // that may itself use LogFile: build it outside the lock, and give a
            // re-entrant call on the same thread a no-op logger instead of
            // recursing.
            if isBuilding {
                return Logger(label: defaultLabel) { _ in SwiftLogNoOpLogHandler() }
            }
            let made = $isBuilding.withValue(true) { Logger(label: defaultLabel) }

            storage.lock.lock()
            defer { storage.lock.unlock() }
            if storage.logger == nil && storage.generation == generation {
                storage.logger = made
            }
            return storage.logger ?? made
        }
        set {
            storage.lock.lock()
            defer { storage.lock.unlock() }
            storage.logger = newValue
            storage.assigned = true
            storage.generation += 1
        }
    }

    static let defaultLabel = "perfect.logfile"

    @TaskLocal private static var isBuilding = false

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var logger: Logger?
        var assigned = false
        var generation = 0
    }

    private static let storage = Storage()

    /// Points ``logger`` at the current backend after a bootstrap. A logger
    /// `LogFile` created itself is dropped (the next use creates a new one); an
    /// assigned logger still labelled `perfect.logfile` is rebuilt with `make`,
    /// keeping its `logLevel` and handler metadata; any other logger is kept.
    static func rebindDefaultLogger(make: () -> Logger = { Logger(label: defaultLabel) }) {
        storage.lock.lock()
        let current = storage.logger
        let assigned = storage.assigned
        let generation = storage.generation
        storage.lock.unlock()

        guard let current else { return }
        let replacement: Logger?
        if !assigned {
            replacement = nil
        } else if current.label == defaultLabel {
            var rebuilt = make()  // outside the lock: runs the LoggingSystem factory
            rebuilt.logLevel = current.logLevel
            for (key, value) in current.handler.metadata {
                rebuilt[metadataKey: key] = value
            }
            replacement = rebuilt
        } else {
            return
        }

        storage.lock.lock()
        defer { storage.lock.unlock() }
        guard storage.generation == generation else { return }  // reassigned meanwhile
        storage.logger = replacement
        storage.generation += 1
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
    /// The event carries `perfect.priority=terminal` metadata, which ``FileLogHandler``
    /// writes as `[EMERG]`. File and console output are written synchronously
    /// before the abort; a ``RemoteLogHandler`` will normally not get the event out.
    public static func terminal(_ message: String, eventid: String = UUID().uuidString) -> Never {
        emit(.terminal, message, eventid)
        fatalError(message)
    }
}
