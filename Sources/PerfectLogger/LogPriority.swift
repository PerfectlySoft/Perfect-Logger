import Logging

/// Friendly Perfect-style log levels. Bridges to swift-log's `Logger.Level`.
///
/// PerfectLogger is built on `apple/swift-log`; this enum exists so callers who
/// prefer the original Perfect naming (`.terminal` for emergencies, etc.) keep a
/// familiar surface. Internally everything maps onto `Logger.Level`.
public enum LogPriority: Int, Comparable, Sendable {
    case debug
    case info
    case warning
    case error
    case critical
    /// Emergency — logged at `.critical` and (via `LogFile.terminal`) aborts the process.
    case terminal

    public static func < (lhs: LogPriority, rhs: LogPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The swift-log level this priority maps to.
    public var level: Logger.Level {
        switch self {
        case .debug:    return .debug
        case .info:     return .info
        case .warning:  return .warning
        case .error:    return .error
        case .critical: return .critical
        case .terminal: return .critical
        }
    }

    /// Bracketed label used by ``FileLogHandler`` when ``LogOptions/priority`` is set.
    func label(even: Bool) -> String {
        switch self {
        case .debug:    return "[DEBUG]"
        case .info:     return even ? "[INFO] " : "[INFO]"
        case .warning:  return even ? "[WARN] " : "[WARNING]"
        case .error:    return "[ERROR]"
        case .critical: return even ? "[CRIT] " : "[CRITICAL]"
        case .terminal: return "[EMERG]"
        }
    }

    init(_ level: Logger.Level) {
        switch level {
        case .trace, .debug:       self = .debug
        case .info, .notice:       self = .info
        case .warning:             self = .warning
        case .error:               self = .error
        case .critical:            self = .critical
        }
    }
}
