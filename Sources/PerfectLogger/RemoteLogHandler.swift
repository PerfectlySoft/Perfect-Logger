import Foundation
import Logging

/// A swift-log `LogHandler` that POSTs each log event to a remote HTTP endpoint.
///
/// Network calls are fire-and-forget (non-blocking) — a failed POST never blocks
/// or throws into the logging call site. Intended for shipping logs to a central
/// collector alongside (not instead of) console/file handlers.
public struct RemoteLogHandler: LogHandler {
    public var logLevel: Logger.Level = .info
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    private let server: String
    private let token: String
    private let label: String

    /// - Parameters:
    ///   - label: The logger label (sent as `source`).
    ///   - server: Base URL of the log collector, e.g. `"https://logs.example.com"`.
    ///   - token: Auth token appended to the path (`/api/v1/log/<token>`).
    public init(label: String, server: String, token: String) {
        self.label = label
        self.server = server
        self.token = token
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        guard !server.isEmpty, !token.isEmpty else { return }

        let merged = self.metadata.merging(event.metadata ?? [:]) { _, new in new }
        let eventid = merged["eventid"].map { "\($0)" } ?? UUID().uuidString

        let server = self.server
        let token = self.token
        let label = self.label
        let payload: [String: Any] = [
            "level": "\(event.level)",
            "label": label,
            "source": event.source,
            "eventid": eventid,
            "message": event.message.description,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        Task.detached {
            guard let url = URL(string: "\(server)/api/v1/log/\(token)") else { return }
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
