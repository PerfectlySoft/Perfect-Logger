import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
@testable import PerfectLogger

@Suite(.serialized)
struct PerfectLoggerTests {

    private func tmpLog() -> String {
        NSTemporaryDirectory() + "PerfectLoggerTests_\(UUID().uuidString).txt"
    }

    /// Builds a `Logger` backed by a `FileLogHandler` at `path`, bypassing the
    /// process-global `LoggingSystem.bootstrap` (which can only run once).
    private func fileLogger(_ path: String, options: LogOptions = .default, level: Logger.Level = .debug) -> Logger {
        Logger(label: "test") { _ in
            var h = FileLogHandler(label: "test", path: path, options: options)
            h.logLevel = level
            return h
        }
    }

    @Test func fileHandlerWritesMessage() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }

        var log = fileLogger(path)
        log[metadataKey: "eventid"] = "evt-123"
        log.critical("boom")

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents.contains("boom"))
        #expect(contents.contains("[CRITICAL]"))
        #expect(contents.contains("evt-123"))
    }

    @Test func allLevelsWrite() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let log = fileLogger(path)
        log.debug("msg-debug")
        log.info("msg-info")
        log.warning("msg-warning")
        log.error("msg-error")
        log.critical("msg-critical")

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        for token in ["msg-debug", "msg-info", "msg-warning", "msg-error", "msg-critical"] {
            #expect(contents.contains(token))
        }
    }

    @Test func levelFiltersLowMessages() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let log = fileLogger(path, level: .error)
        log.debug("should-not-appear")
        log.info("should-not-appear-either")
        log.error("should-appear")

        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        #expect(!contents.contains("should-not-appear"))
        #expect(contents.contains("should-appear"))
    }

    @Test func noneOptionWritesMessageOnly() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let log = fileLogger(path, options: .none)
        log.error("bare message")

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents.trimmingCharacters(in: .whitespacesAndNewlines) == "bare message")
    }

    @Test func appendsAcrossWrites() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let log = fileLogger(path)
        log.error("line-one")
        log.error("line-two")
        log.error("line-three")

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        for token in ["line-one", "line-two", "line-three"] {
            #expect(contents.contains(token))
        }
    }

    @Test func logFileFacadeReturnsAndReusesEventId() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Point the façade's logger at our temp file.
        LogFile.logger = fileLogger(path)

        let eid = LogFile.error("first message")
        LogFile.error("second message", eventid: eid)

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let occurrences = contents.components(separatedBy: eid).count - 1
        #expect(occurrences == 2)
        #expect(contents.contains("first message"))
        #expect(contents.contains("second message"))
    }

    @Test func priorityMapsToSwiftLogLevel() {
        #expect(LogPriority.debug.level == .debug)
        #expect(LogPriority.warning.level == .warning)
        #expect(LogPriority.terminal.level == .critical)
    }

    // MARK: Line format and metadata

    private func event(
        _ level: Logger.Level = .error,
        _ message: Logger.Message = "msg",
        metadata: Logger.Metadata? = nil,
        error: (any Error)? = nil
    ) -> LogEvent {
        LogEvent(level: level, message: message, error: error, metadata: metadata,
                 source: "src", file: #fileID, function: #function, line: #line)
    }

    private func handler(options: LogOptions = .default) -> FileLogHandler {
        FileLogHandler(label: "test", path: tmpLog(), options: options)
    }

    @Test func defaultLineFormatIsUnchangedWithOnlyAnEventId() throws {
        let line = handler().line(for: event(metadata: ["eventid": "E1"]), date: Date(timeIntervalSince1970: 0))
        let pattern = #"^\[ERROR\] \[E1\] \[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} GMT([+-]\d{2}:\d{2})?\] msg\n$"#
        #expect(line.range(of: pattern, options: .regularExpression) != nil, "\(line)")
    }

    @Test func timestampUsesPosixGregorianFormat() {
        // 2001-02-03 04:05:06 UTC; whatever the local zone, the digits must be ASCII
        // and the year Gregorian (a Buddhist or Japanese calendar would change it).
        let date = Date(timeIntervalSince1970: 981_173_106)
        let line = handler(options: .timestamp).line(for: event(), date: date)
        let stamp = String(line.dropFirst().prefix(while: { $0 != "]" }))
        #expect(stamp.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} GMT([+-]\d{2}:\d{2})?$"#, options: .regularExpression) != nil, "\(stamp)")
        #expect(stamp.allSatisfy { $0.isASCII })
        #expect(stamp.hasPrefix("2001-02-0"))
    }

    @Test func extraMetadataIsAppendedSortedAfterTheMessage() {
        var h = handler()
        h[metadataKey: "zone"] = "handler"
        h[metadataKey: "shared"] = "handler"
        h.metadataProvider = Logger.MetadataProvider { ["provided": "yes", "shared": "provider"] }
        let line = h.line(for: event(metadata: ["eventid": "E2", "request": "42", "shared": "call"]),
                          date: Date())
        #expect(line.hasPrefix("[ERROR] [E2] ["))
        #expect(line.hasSuffix("] msg provided=yes request=42 shared=call zone=handler\n"), "\(line)")
        #expect(line.components(separatedBy: "E2").count == 2, "eventid is not repeated")
    }

    @Test func providerMetadataIsMergedThroughALogger() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let provider = Logger.MetadataProvider { ["trace": "t-1"] }
        let log = Logger(label: "test") { label in
            FileLogHandler(label: label, path: path, metadataProvider: provider)
        }
        log.info("with provider")
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents.contains("with provider trace=t-1"), "\(contents)")
    }

    @Test func errorIsRenderedAsMetadata() {
        struct Boom: Error, CustomStringConvertible { var description: String { "kaboom" } }
        let line = handler(options: .metadata).line(for: event(error: Boom()), date: Date())
        #expect(line.contains("error.message=kaboom"), "\(line)")
        #expect(line.contains("error.type="))
    }

    @Test func metadataIsOmittedWithoutTheOption() {
        let options: [LogOptions] = [.none, [.priority, .eventId, .timestamp]]
        for options in options {
            let line = handler(options: options).line(for: event(metadata: ["k": "v", "eventid": "E"]), date: Date())
            #expect(!line.contains("k=v"), "\(line)")
        }
        #expect(handler(options: .none).line(for: event(metadata: ["k": "v"]), date: Date()) == "msg\n")
    }

    @Test func terminalIsLabelledEmergency() throws {
        let line = handler(options: .priority).line(
            for: event(.critical, metadata: ["priority": "terminal", "eventid": "E"]), date: Date())
        #expect(line == "[EMERG] msg\n")
        let plain = handler(options: .priority).line(for: event(.critical), date: Date())
        #expect(plain == "[CRITICAL] msg\n")
    }

    @Test func debugMessageIsNotEvaluatedWhenFiltered() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        LogFile.logger = fileLogger(path, level: .info)
        var evaluated = false
        LogFile.debug({ evaluated = true; return "hidden" }())
        #expect(!evaluated)
    }

    // MARK: File sink robustness

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/dev/full")))
    func fullDiskDoesNotCrash() {
        // /dev/full fails every write with ENOSPC. The legacy FileHandle APIs raised
        // (or trapped) here; the sink must drop the line and carry on.
        let log = fileLogger("/dev/full")
        for i in 0..<100 { log.error("cannot be written \(i)") }
    }

    @Test func unopenableFileDisablesHandlerQuietly() {
        let dir = NSTemporaryDirectory() + "PerfectLoggerTests_missing_\(UUID().uuidString)/nested/app.log"
        #expect(FileSink.sink(for: dir) == nil)
        fileLogger(dir).error("dropped")  // must not crash
    }

    @Test func concurrentWritesProduceWholeLines() async throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let tasks = 8, perTask = 250
        await withTaskGroup(of: Void.self) { group in
            for t in 0..<tasks {
                group.addTask {
                    let log = fileLogger(path)
                    for i in 0..<perTask { log.info("task \(t) line \(i)", metadata: ["eventid": "e"]) }
                }
            }
        }
        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == tasks * perTask)
        #expect(lines.allSatisfy { $0.hasPrefix("[INFO] [e] [") && $0.contains("] task ") })
    }

    @Test func logFileLoggerIsSafeToSwapWhileLogging() async throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        await withTaskGroup(of: Void.self) { group in
            for t in 0..<4 {
                group.addTask {
                    for i in 0..<200 {
                        if t == 0 && i % 20 == 0 { LogFile.logger = fileLogger(path) }
                        LogFile.info("swap \(t) \(i)")
                    }
                }
            }
        }
    }

    // MARK: Remote handler

    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var requests: [URLRequest] = []
        var inFlight = 0
        var maxInFlight = 0

        func record(_ request: URLRequest) async {
            begin(request)
            try? await Task.sleep(nanoseconds: 1_000_000)
            end()
        }

        private func begin(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            requests.append(request)
        }

        private func end() {
            lock.lock(); defer { lock.unlock() }
            inFlight -= 1
        }

        var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    @Test func remoteHandlerPostsJSONWithMetadata() async throws {
        let recorder = Recorder()
        let url = try #require(RemoteSink.collectorURL(server: "https://logs.example.com/", token: "a b/c"))
        #expect(url.absoluteString == "https://logs.example.com/api/v1/log/a%20b%2Fc")
        let sink = RemoteSink(url: url) { await recorder.record($0) }
        let log = Logger(label: "remote") { _ in
            RemoteLogHandler(label: "remote", sink: sink, metadataProvider: .init { ["trace": "t"] })
        }
        log.warning("hello", metadata: ["eventid": "E9", "user": "tim"])
        await waitFor { recorder.count == 1 }

        let request = try #require(recorder.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == url)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let entry = try JSONDecoder().decode(RemoteLogEntry.self, from: try #require(request.httpBody))
        #expect(entry.level == "warning")
        #expect(entry.label == "remote")
        #expect(entry.eventid == "E9")
        #expect(entry.message == "hello")
        #expect(entry.metadata == ["trace": "t", "user": "tim"])
        #expect(entry.timestamp.hasSuffix("Z"))
    }

    @Test func remoteQueueIsBoundedAndSerial() async throws {
        let recorder = Recorder()
        let sink = RemoteSink(url: URL(string: "http://localhost:9/x")!, capacity: 10) { await recorder.record($0) }
        for i in 0..<1_000 { sink.enqueue(Data("\(i)".utf8)) }
        await waitFor { recorder.count + sink.dropped == 1_000 }
        #expect(sink.dropped >= 1_000 - 11)
        #expect(recorder.count <= 11)
        #expect(recorder.maxInFlight == 1)

        // The sink keeps working after draining.
        sink.enqueue(Data("again".utf8))
        let before = recorder.count
        await waitFor { recorder.count == before + 1 }
        #expect(recorder.count == before + 1)
    }

    @Test func remoteConfigurationIsValidated() {
        #expect(RemoteSink.collectorURL(server: "", token: "t") == nil)
        #expect(RemoteSink.collectorURL(server: "https://logs.example.com", token: "") == nil)
        #expect(RemoteSink.collectorURL(server: "logs.example.com", token: "t") == nil)
        #expect(RemoteSink.sink(server: "", token: "t") == nil)
    }
}
