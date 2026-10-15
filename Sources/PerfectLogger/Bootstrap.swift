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
    ///   - remoteToken: Auth token for the collector. Required if `remoteServer` is
    ///     set; without one (or with a malformed server URL) remote logging is
    ///     disabled and a warning is printed on standard error.
    ///   - level: Minimum level for all handlers. Default `.info`.
    ///   - metadataProvider: Optional swift-log metadata provider, installed as the
    ///     global provider and merged into every handler's events. Default `nil`.
    public static func bootstrap(
        console: Bool = true,
        file: String? = nil,
        fileOptions: LogOptions = .default,
        remoteServer: String? = nil,
        remoteToken: String? = nil,
        level: Logger.Level = .info,
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        // Resolve the collector once, so a bad configuration warns once rather
        // than once per Logger.
        let remote = remoteServer.flatMap { RemoteSink.sink(server: $0, token: remoteToken ?? "") }

        LoggingSystem.bootstrap({ label, provider in
            var handlers: [any LogHandler] = []

            if console {
                var h = StreamLogHandler.standardOutput(label: label, metadataProvider: provider)
                h.logLevel = level
                handlers.append(h)
            }
            if let file {
                var h = FileLogHandler(label: label, path: file, options: fileOptions, metadataProvider: provider)
                h.logLevel = level
                handlers.append(h)
            }
            if let remote {
                var h = RemoteLogHandler(label: label, sink: remote, metadataProvider: provider)
                h.logLevel = level
                handlers.append(h)
            }

            switch handlers.count {
            case 0:  return SwiftLogNoOpLogHandler()
            case 1:  return handlers[0]
            default: return MultiplexLogHandler(handlers)
            }
        }, metadataProvider: metadataProvider)

        LogFile.rebindDefaultLogger()
    }
}
