import Foundation
import Logging

/// Thread-safe append-only sink for a single file path. Shared across all
/// ``FileLogHandler`` copies targeting the same path (swift-log copies handlers
/// per `Logger`, so the underlying file handle must be shared).
final class FileSink: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()

    private init(handle: FileHandle) { self.handle = handle }

    func write(_ string: String) {
        lock.lock()
        defer { lock.unlock() }
        handle.seekToEndOfFile()
        handle.write(Data(string.utf8))
    }

    // MARK: Registry

    nonisolated(unsafe) private static var sinks: [String: FileSink] = [:]
    private static let registryLock = NSLock()

    /// Returns the shared sink for `path`, creating the file if needed.
    /// Returns `nil` if the file cannot be opened for writing.
    static func sink(for path: String) -> FileSink? {
        registryLock.lock()
        defer { registryLock.unlock() }

        if let existing = sinks[path] { return existing }

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        let sink = FileSink(handle: handle)
        sinks[path] = sink
        return sink
    }
}

/// A swift-log `LogHandler` that appends formatted lines to a file.
///
/// Line format is controlled by ``LogOptions`` — by default each line is
/// `"[LEVEL] [eventid] [timestamp] message"`. The event ID is read from the
/// `eventid` metadata key (which ``LogFile`` populates automatically).
public struct FileLogHandler: LogHandler {
    public var logLevel: Logger.Level = .debug
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    /// Which prefix fields to write ahead of each message.
    public var options: LogOptions

    /// When `true`, shorter level labels are padded so columns align.
    public var even: Bool

    private let sink: FileSink?

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return f
    }()

    public init(label: String, path: String, options: LogOptions = .default, even: Bool = false) {
        self.options = options
        self.even = even
        self.sink = FileSink.sink(for: path)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        guard let sink else { return }

        let merged = self.metadata.merging(event.metadata ?? [:]) { _, new in new }
        var parts: [String] = []

        if options.contains(.priority) {
            parts.append(LogPriority(event.level).label(even: even))
        }
        if options.contains(.eventId), let eid = merged["eventid"] {
            parts.append("[\(eid)]")
        }
        if options.contains(.timestamp) {
            parts.append("[\(Self.timestampFormatter.string(from: Date()))]")
        }
        parts.append(event.message.description)

        sink.write(parts.joined(separator: " ") + "\n")
    }
}
