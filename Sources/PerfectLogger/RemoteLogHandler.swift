import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// A swift-log `LogHandler` that POSTs each log event to a remote HTTP endpoint.
///
/// Network calls are fire-and-forget (non-blocking) — a failed POST never blocks
/// or throws into the logging call site. Intended for shipping logs to a central
/// collector alongside (not instead of) console/file handlers.
///
/// Events are queued per collector URL and sent one at a time by a single
/// background task. At most ``maxPendingEvents`` events wait in the queue; while
/// it is full, new events are dropped rather than buffered without limit. Events
/// still queued when the process exits (including via ``LogFile/terminal(_:eventid:)``)
/// are lost.
///
/// Each event is sent as a JSON object with the keys `level`, `label`, `source`,
/// `eventid`, `message`, `timestamp` (ISO 8601, UTC) and, when the merged
/// metadata holds keys other than `eventid`, `metadata` (string values).
public struct RemoteLogHandler: LogHandler {
    public var logLevel: Logger.Level = .info
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    /// The most events that may wait to be sent to one collector.
    public static let maxPendingEvents = RemoteSink.defaultCapacity

    private let label: String
    private let sink: RemoteSink?

    /// - Parameters:
    ///   - label: The logger label (sent as `label`).
    ///   - server: Base URL of the log collector, e.g. `"https://logs.example.com"`.
    ///   - token: Auth token appended to the path (`/api/v1/log/<token>`). It is
    ///     part of the URL, so use HTTPS and keep it out of proxy access logs.
    ///   - metadataProvider: Optional provider whose metadata is merged into each event.
    public init(label: String, server: String, token: String, metadataProvider: Logger.MetadataProvider? = nil) {
        self.init(label: label, sink: RemoteSink.sink(server: server, token: token), metadataProvider: metadataProvider)
    }

    init(label: String, sink: RemoteSink?, metadataProvider: Logger.MetadataProvider? = nil) {
        self.label = label
        self.sink = sink
        self.metadataProvider = metadataProvider
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        guard let sink else { return }

        var merged = effectiveMetadata(base: metadata, provider: metadataProvider, event: event)
        let eventid = merged.removeValue(forKey: "eventid").map { "\($0)" } ?? UUID().uuidString

        let entry = RemoteLogEntry(
            level: "\(event.level)",
            label: label,
            source: event.source,
            eventid: eventid,
            message: event.message.description,
            timestamp: Date().formatted(.iso8601),
            metadata: merged.isEmpty ? nil : merged.mapValues { "\($0)" }
        )
        guard let body = try? JSONEncoder().encode(entry) else { return }
        sink.enqueue(body)
    }
}

/// The JSON body ``RemoteLogHandler`` POSTs for each event.
struct RemoteLogEntry: Codable, Equatable {
    var level: String
    var label: String
    var source: String
    var eventid: String
    var message: String
    var timestamp: String
    var metadata: [String: String]?
}

/// A bounded FIFO of encoded events for one collector URL, drained by at most
/// one task at a time.
final class RemoteSink: @unchecked Sendable {
    typealias Transport = @Sendable (URLRequest) async -> Void

    static let defaultCapacity = 1_000

    let url: URL
    private let capacity: Int
    private let transport: Transport

    private let lock = NSLock()
    private var pending: [Data] = []
    private var head = 0
    private var draining = false
    private var droppedCount = 0

    init(url: URL, capacity: Int = RemoteSink.defaultCapacity, transport: @escaping Transport = RemoteSink.urlSession) {
        self.url = url
        self.capacity = capacity
        self.transport = transport
    }

    /// Number of events dropped so far because the queue was full.
    var dropped: Int {
        lock.lock()
        defer { lock.unlock() }
        return droppedCount
    }

    func enqueue(_ body: Data) {
        lock.lock()
        guard pending.count - head < capacity else {
            droppedCount += 1
            lock.unlock()
            return
        }
        pending.append(body)
        let start = !draining
        draining = true
        lock.unlock()

        if start {
            Task.detached(priority: .utility) { await self.drain() }
        }
    }

    private func next() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard head < pending.count else {
            pending.removeAll(keepingCapacity: true)
            head = 0
            draining = false
            return nil
        }
        let body = pending[head]
        head += 1
        if head >= 256 && head * 2 >= pending.count {
            pending.removeFirst(head)
            head = 0
        }
        return body
    }

    private func drain() async {
        while let body = next() {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            await transport(request)
        }
    }

    static let urlSession: Transport = { request in
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: Registry

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var sinks: [String: RemoteSink?] = [:]
    }

    private static let registry = Registry()

    /// The shared sink for `<server>/api/v1/log/<token>`, or `nil` when either is
    /// empty or they don't form an http(s) URL. The first failure for a given
    /// server and token prints one warning on standard error.
    static func sink(server: String, token: String) -> RemoteSink? {
        let key = server + "\u{0}" + token
        registry.lock.lock()
        defer { registry.lock.unlock() }
        if let existing = registry.sinks[key] { return existing }
        let sink = collectorURL(server: server, token: token).map { RemoteSink(url: $0) }
        if sink == nil {
            FileHandle.standardError.writeWarning("PerfectLogger: invalid remote log server '\(server)' or empty token; remote logging is disabled.\n")
        }
        registry.sinks[key] = .some(sink)
        return sink
    }

    static func collectorURL(server: String, token: String) -> URL? {
        var base = server
        while base.hasSuffix("/") { base.removeLast() }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        guard !base.isEmpty, !token.isEmpty,
              let encoded = token.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "\(base)/api/v1/log/\(encoded)"),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}
