import Foundation
import Logging

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Thread-safe append-only sink for a single file path. Shared across all
/// ``FileLogHandler`` copies targeting the same path (swift-log copies handlers
/// per `Logger`, so the underlying file descriptor must be shared).
///
/// The file is opened with `O_APPEND`, so every line lands at the current end of
/// the file even when another process (or `logrotate`'s `copytruncate`) changes
/// it underneath us, and each line is a single `write(2)`. Write errors such as a
/// full disk are swallowed: a logger must never take the process down.
final class FileSink: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()

    private init(fd: Int32) { self.fd = fd }

    deinit { close(fd) }

    func write(_ string: String) {
        var bytes = Array(string.utf8)
        guard !bytes.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        bytes.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = systemWrite(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n > 0 {
                    offset += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    return  // ENOSPC, EIO, EBADF, ...: drop the rest of the line
                }
            }
        }
    }

    // MARK: Registry

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var sinks: [String: FileSink] = [:]
        var warned: Set<String> = []
    }

    private static let registry = Registry()

    /// Returns the shared sink for `path`, creating the file (mode 0644) if needed.
    /// Returns `nil` if the file cannot be opened for writing (the next handler
    /// for the path retries); the first failure per path prints one warning on
    /// standard error.
    static func sink(for path: String) -> FileSink? {
        registry.lock.lock()
        defer { registry.lock.unlock() }

        if let existing = registry.sinks[path] { return existing }

        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let reason = String(cString: strerror(errno))
            guard registry.warned.insert(path).inserted else { return nil }
            FileHandle.standardError.writeWarning("PerfectLogger: cannot open log file '\(path)' (\(reason)); file logging to it is disabled.\n")
            return nil
        }
        let sink = FileSink(fd: fd)
        registry.sinks[path] = sink
        return sink
    }
}

@inline(__always)
private func systemWrite(_ fd: Int32, _ buf: UnsafeRawPointer, _ count: Int) -> Int {
    #if canImport(Darwin)
    return Darwin.write(fd, buf, count)
    #elseif canImport(Glibc)
    return Glibc.write(fd, buf, count)
    #else
    return Musl.write(fd, buf, count)
    #endif
}

extension FileHandle {
    /// Best-effort diagnostic write that can never raise or throw.
    func writeWarning(_ message: String) {
        try? write(contentsOf: Data(message.utf8))
    }
}

/// Renders the `[timestamp]` field. `DateFormatter` output depends on the user's
/// locale and calendar unless both are pinned, and sharing one instance across
/// threads is only documented as safe on Apple platforms, so the instance is
/// configured with `en_US_POSIX` / Gregorian and guarded by a lock.
private final class TimestampFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: DateFormatter

    init() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        formatter = f
    }

    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }
}

/// A swift-log `LogHandler` that appends formatted lines to a file.
///
/// Line format is controlled by ``LogOptions`` — by default each line is
/// `"[LEVEL] [eventid] [timestamp] message"`. The event ID is read from the
/// `eventid` metadata key (which ``LogFile`` populates automatically).
///
/// Metadata from the handler, its `metadataProvider` and the log call are merged
/// (later sources win, as in swift-log's `StreamLogHandler`). When
/// ``LogOptions/metadata`` is set and that metadata holds keys other than
/// `eventid`, they are appended after the message as sorted `key=value` pairs;
/// lines without extra metadata are unchanged.
public struct FileLogHandler: LogHandler {
    public var logLevel: Logger.Level = .debug
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    /// Which prefix fields to write ahead of each message.
    public var options: LogOptions

    /// When `true`, shorter level labels are padded so columns align.
    public var even: Bool

    private let sink: FileSink?

    private static let timestampFormatter = TimestampFormatter()

    public init(
        label: String,
        path: String,
        options: LogOptions = .default,
        even: Bool = false,
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        self.options = options
        self.even = even
        self.metadataProvider = metadataProvider
        self.sink = FileSink.sink(for: path)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        guard let sink else { return }
        sink.write(line(for: event, date: Date()))
    }

    /// Formats one log line, including the trailing newline.
    func line(for event: LogEvent, date: Date) -> String {
        var merged = effectiveMetadata(base: metadata, provider: metadataProvider, event: event)
        var parts: [String] = []

        let priority = LogPriority(event: event, metadata: merged)
        if priority == .terminal { merged.removeValue(forKey: LogPriority.metadataKey) }

        if options.contains(.priority) {
            parts.append(priority.label(even: even))
        }
        let eventid = merged.removeValue(forKey: "eventid")
        if options.contains(.eventId), let eventid {
            parts.append("[\(eventid)]")
        }
        if options.contains(.timestamp) {
            parts.append("[\(Self.timestampFormatter.string(from: date))]")
        }
        parts.append(event.message.description)
        if options.contains(.metadata), !merged.isEmpty {
            parts.append(merged.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }

        return parts.joined(separator: " ") + "\n"
    }
}

/// Merges handler metadata, metadata-provider output, the call's metadata and
/// the call's error the way swift-log's `StreamLogHandler` does: each later
/// source overrides earlier keys.
func effectiveMetadata(base: Logger.Metadata, provider: Logger.MetadataProvider?, event: LogEvent) -> Logger.Metadata {
    var merged = base
    if let provided = provider?.get(), !provided.isEmpty {
        merged.merge(provided) { _, new in new }
    }
    if let explicit = event.metadata, !explicit.isEmpty {
        merged.merge(explicit) { _, new in new }
    }
    if let error = event.error {
        merged["error.message"] = "\(error)"
        merged["error.type"] = "\(String(reflecting: type(of: error)))"
    }
    return merged
}
