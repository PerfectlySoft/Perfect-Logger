import Foundation
import Logging

/// Namespace for PerfectLogger's bootstrap convenience.
public enum PerfectLogger {

    /// Configures the global swift-log backend in one call.
    ///
    /// Combines any of console / file / remote handlers via `MultiplexLogHandler`.
    /// Call this once, early in app startup — `LoggingSystem.bootstrap` may only
    /// be called a single time per process.
    ///
    /// - Parameters:
    ///   - console: Echo to stdout (swift-log's `StreamLogHandler`). Default `true`.
    ///   - file: Optional path to append structured lines to (``FileLogHandler``).
    ///   - fileOptions: Prefix fields for the file handler. Default `.default`.
    ///   - remoteServer: Optional collector base URL (``RemoteLogHandler``).
    ///   - remoteToken: Auth token for the collector. Required if `remoteServer` is set.
    ///   - level: Minimum level for all handlers. Default `.info`.
    public static func bootstrap(
        console: Bool = true,
        file: String? = nil,
        fileOptions: LogOptions = .default,
        remoteServer: String? = nil,
        remoteToken: String? = nil,
        level: Logger.Level = .info
    ) {
        LoggingSystem.bootstrap { label in
            var handlers: [any LogHandler] = []

            if console {
                var h = StreamLogHandler.standardOutput(label: label)
                h.logLevel = level
                handlers.append(h)
            }
            if let file {
                var h = FileLogHandler(label: label, path: file, options: fileOptions)
                h.logLevel = level
                handlers.append(h)
            }
            if let remoteServer, let remoteToken {
                var h = RemoteLogHandler(label: label, server: remoteServer, token: remoteToken)
                h.logLevel = level
                handlers.append(h)
            }

            switch handlers.count {
            case 0:  return SwiftLogNoOpLogHandler()
            case 1:  return handlers[0]
            default: return MultiplexLogHandler(handlers)
            }
        }
    }
}
