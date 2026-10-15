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
/// full disk drop the line. Writing to a pipe or FIFO whose reader has gone away
/// fails with `EPIPE` instead of raising `SIGPIPE`.
final class FileSink: @unchecked Sendable {
    private let fd: Int32
    private let isRegularFile: Bool
    private let lock = NSLock()

    private init(fd: Int32, isRegularFile: Bool) {
        self.fd = fd
        self.isRegularFile = isRegularFile
    }

    deinit { close(fd) }

    func write(_ string: String) {
        let bytes = Array(string.utf8)
        guard !bytes.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        withSIGPIPESuppressed(!isRegularFile) {
            let written = writeAll(bytes)
            if written > 0 && written < bytes.count && bytes.last == UInt8(ascii: "\n") {
                // Terminate the partial line so the next one starts on its own line.
                _ = writeAll([UInt8(ascii: "\n")])
            }
        }
    }

    /// Writes as much of `bytes` as possible, retrying `EINTR`; returns the count written.
    private func writeAll(_ bytes: [UInt8]) -> Int {
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = systemWrite(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n > 0 {
                    offset += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    break  // ENOSPC, EIO, EPIPE, EAGAIN, ...: drop the rest
                }
            }
            return offset
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
    /// Returns `nil` if the path cannot be opened for writing, or names a
    /// directory, socket or block device (the next handler for the path
    /// retries); the first failure per path prints one warning on standard error.
    ///
    /// A FIFO is opened without blocking, so one with no reader is refused
    /// (`ENXIO`) instead of hanging the caller.
    static func sink(for path: String) -> FileSink? {
        registry.lock.lock()
        defer { registry.lock.unlock() }

        if let existing = registry.sinks[path] { return existing }

        func refuse(_ reason: String) -> FileSink? {
            if registry.warned.insert(path).inserted {
                FileHandle.standardError.writeWarning("PerfectLogger: cannot open log file '\(path)' (\(reason)); file logging to it is disabled.\n")
            }
            return nil
        }

        var info = stat()
        if stat(path, &info) == 0 {
            switch info.st_mode & S_IFMT {
            case S_IFREG, S_IFCHR, S_IFIFO: break
            case S_IFDIR: return refuse("is a directory")
            default: return refuse("not a regular file, character device or FIFO")
            }
        }

        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NONBLOCK, 0o644)
        guard fd >= 0 else { return refuse(String(cString: strerror(errno))) }

        // Blocking writes from here on; O_NONBLOCK was only for the open.
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
        #if canImport(Darwin)
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        #endif

        var opened = stat()
        let isRegular = fstat(fd, &opened) == 0 && (opened.st_mode & S_IFMT) == S_IFREG
        let sink = FileSink(fd: fd, isRegularFile: isRegular)
        registry.sinks[path] = sink
        return sink
    }
}

/// Runs `body` so that a write to a broken pipe fails with `EPIPE` rather than
/// killing the process. Darwin uses `F_SETNOSIGPIPE` on the descriptor; on
/// Linux `SIGPIPE` is blocked on the calling thread for the duration and any
/// `SIGPIPE` the body raised is consumed before the mask is restored.
private func withSIGPIPESuppressed(_ needed: Bool, _ body: () -> Void) {
    #if os(Linux)
    guard needed else { return body() }
    var sigpipe = sigset_t()
    sigemptyset(&sigpipe)
    sigaddset(&sigpipe, SIGPIPE)
    var previous = sigset_t()
    var pendingBefore = sigset_t()
    sigpending(&pendingBefore)
    let alreadyPending = sigismember(&pendingBefore, SIGPIPE) == 1
    pthread_sigmask(SIG_BLOCK, &sigpipe, &previous)
    body()
    if !alreadyPending {
        var pending = sigset_t()
        sigpending(&pending)
        if sigismember(&pending, SIGPIPE) == 1 {
            var zero = timespec(tv_sec: 0, tv_nsec: 0)
            _ = sigtimedwait(&sigpipe, nil, &zero)
        }
    }
    pthread_sigmask(SIG_SETMASK, &previous, nil)
    #else
    body()
    #endif
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
            parts.append(merged.sorted { $0.key < $1.key }
                .map { "\(escapeMetadataField($0.key))=\(escapeMetadataField(renderMetadataValue($0.value)))" }
                .joined(separator: " "))
        }

        return parts.joined(separator: " ") + "\n"
    }
}

/// Renders a metadata value as text. Dictionaries are rendered with their keys
/// sorted, so output is stable: `[a: 1, b: [x, y]]`.
func renderMetadataValue(_ value: Logger.MetadataValue) -> String {
    switch value {
    case .string(let string):
        return string
    case .stringConvertible(let convertible):
        return convertible.description
    case .array(let values):
        return "[" + values.map(renderMetadataValue).joined(separator: ", ") + "]"
    case .dictionary(let dictionary):
        return "[" + dictionary.sorted { $0.key < $1.key }
            .map { "\($0.key): \(renderMetadataValue($0.value))" }
            .joined(separator: ", ") + "]"
    }
}

/// Makes a metadata key or value safe to put in a single log line: `\`, `"`,
/// `\n`, `\r` and `\t` are backslash-escaped, other control characters become
/// `\u{XX}`, and the result is double-quoted if it is empty or contains a
/// space, `=` or `"`. A value can therefore neither start a forged line nor
/// blur where one `key=value` pair ends.
func escapeMetadataField(_ text: String) -> String {
    var escaped = ""
    var needsQuotes = text.isEmpty
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": escaped += "\\\\"
        case "\"": escaped += "\\\""; needsQuotes = true
        case "\n": escaped += "\\n"
        case "\r": escaped += "\\r"
        case "\t": escaped += "\\t"
        case " ", "=": escaped.unicodeScalars.append(scalar); needsQuotes = true
        default:
            if scalar.properties.generalCategory == .control || scalar == "\u{2028}" || scalar == "\u{2029}" {
                escaped += "\\u{" + String(scalar.value, radix: 16) + "}"
            } else {
                escaped.unicodeScalars.append(scalar)
            }
        }
    }
    return needsQuotes ? "\"" + escaped + "\"" : escaped
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
