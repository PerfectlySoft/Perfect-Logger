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

    /// A handler for exercising `line(for:date:)`; it never needs a real file.
    private func handler(options: LogOptions = .default) -> FileLogHandler {
        FileLogHandler(label: "test", path: "/dev/null", options: options)
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

    @Test func metadataCannotForgeLinesOrPairs() {
        let forged = "tim\n[CRITICAL] [forged-id] [2026-01-01 00:00:00 GMT] admin password changed"
        let line = handler(options: .metadata).line(
            for: event(metadata: ["user": .string(forged), "a b=c": "d e", "q": "say \"hi\"\\", "e": "", "ctl": "\u{1b}[31m\r\t"]),
            date: Date())
        #expect(line.filter { $0 == "\n" }.count == 1 && line.hasSuffix("\n"), "\(line)")
        #expect(line == #"msg "a b=c"="d e" ctl=\u{1b}[31m\r\t e="" q="say \"hi\"\\" user="tim\n[CRITICAL] [forged-id] [2026-01-01 00:00:00 GMT] admin password changed""# + "\n")
    }

    @Test func nestedMetadataIsSorted() {
        let line = handler(options: .metadata).line(
            for: event(metadata: ["d": ["z": "1", "a": "2", "m": ["y": "3", "b": "4"]], "l": ["x", "y"]]), date: Date())
        #expect(line == #"msg d="[a: 2, m: [b: 4, y: 3], z: 1]" l="[x, y]""# + "\n")
    }

    @Test func userPriorityMetadataIsNotTheTerminalMarker() {
        let line = handler(options: [.priority, .metadata]).line(
            for: event(.critical, metadata: ["priority": "terminal"]), date: Date())
        #expect(line == "[CRITICAL] msg priority=terminal\n")
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
            for: event(.critical, metadata: ["perfect.priority": "terminal", "eventid": "E"]), date: Date())
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

    @Test func directoryIsRefused() {
        #expect(FileSink.sink(for: NSTemporaryDirectory()) == nil)
    }

    @Test func fifoWithoutAReaderDoesNotHang() throws {
        let path = NSTemporaryDirectory() + "PerfectLoggerTests_fifo_\(UUID().uuidString)"
        defer { unlink(path) }
        try #require(mkfifo(path, 0o600) == 0)
        #expect(FileSink.sink(for: path) == nil)  // ENXIO instead of blocking in open(2)
    }

    @Test func brokenPipeDoesNotKillTheProcess() throws {
        let path = NSTemporaryDirectory() + "PerfectLoggerTests_fifo_\(UUID().uuidString)"
        defer { unlink(path) }
        try #require(mkfifo(path, 0o600) == 0)
        let reader = open(path, O_RDONLY | O_NONBLOCK)
        try #require(reader >= 0)
        let log = fileLogger(path)
        log.info("while the reader is there")
        close(reader)
        log.info("after the reader left")  // EPIPE; SIGPIPE would end the test run here
        log.info("and again")
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

    // MARK: Rebinding LogFile.logger

    @Test func rebindRebuildsAModifiedDefaultLogger() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        // What `LogFile.logger.logLevel = .debug` before bootstrap leaves behind:
        // an assigned logger with the default label, bound to the old backend.
        var before = Logger(label: LogFile.defaultLabel) { FileLogHandler(label: $0, path: "/dev/null") }
        before.logLevel = .debug
        before[metadataKey: "app"] = "demo"
        LogFile.logger = before

        LogFile.rebindDefaultLogger { fileLogger(path, level: .error) }
        LogFile.debug("rebound")

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents.contains("rebound app=demo"), "\(contents)")
        #expect(LogFile.logger.logLevel == .debug)
    }

    @Test func rebindKeepsACustomLogger() throws {
        let path = tmpLog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        LogFile.logger = Logger(label: "custom") { FileLogHandler(label: $0, path: path) }
        LogFile.rebindDefaultLogger { Issue.record("must not rebuild"); return Logger(label: "x") }
        LogFile.error("kept")
        #expect(LogFile.logger.label == "custom")
        #expect(try String(contentsOfFile: path, encoding: .utf8).contains("kept"))
    }

    // MARK: Remote handler

    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var requests: [URLRequest] = []
        var inFlight = 0
        var maxInFlight = 0

        func record(_ request: URLRequest, during work: () async -> Void = {}) async {
            begin(request)
            await work()
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

    /// Holds every caller until ``open()``.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { continuation in
                if !enqueue(continuation) { continuation.resume() }
            }
        }

        private func enqueue(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if isOpen { return false }
            waiters.append(continuation)
            return true
        }

        func open() {
            lock.lock()
            isOpen = true
            let waiting = waiters
            waiters = []
            lock.unlock()
            waiting.forEach { $0.resume() }
        }
    }

    @Test func remoteQueueIsBoundedAndSerial() async throws {
        let recorder = Recorder()
        let gate = Gate()
        let sink = RemoteSink(url: URL(string: "http://localhost:18431/x")!, capacity: 10) { request in
            await recorder.record(request) { await gate.wait() }
        }
        sink.enqueue(Data("first".utf8))
        await waitFor { recorder.count == 1 }     // the drain task is now stuck in the transport
        for i in 0..<1_000 { sink.enqueue(Data("\(i)".utf8)) }
        #expect(sink.dropped == 990)              // exactly `capacity` wait behind the first

        gate.open()
        await waitFor { recorder.count == 11 }
        #expect(recorder.count == 11)
        #expect(recorder.maxInFlight == 1)
        let bodies = recorder.requests.compactMap { $0.httpBody.map { String(decoding: $0, as: UTF8.self) } }
        let expected: [String] = ["first"] + (0..<10).map { String($0) }
        #expect(bodies == expected)

        // The sink keeps working after draining.
        sink.enqueue(Data("again".utf8))
        await waitFor { recorder.count == 12 }
        #expect(recorder.count == 12)
    }

    @Test func remoteTimeoutBoundsATransportThatNeverReturns() async throws {
        // The first request hangs forever and ignores cancellation; the next one
        // must still go out once the timeout passes.
        let recorder = Recorder()
        let hung = Gate()
        let sink = RemoteSink(url: URL(string: "http://localhost:18431/x")!, timeout: 0.2) { request in
            let first = String(decoding: request.httpBody ?? Data(), as: UTF8.self) == "hang"
            await recorder.record(request) { if first { await hung.wait() } }
        }
        defer { hung.open() }
        let start = Date()
        sink.enqueue(Data("hang".utf8))
        sink.enqueue(Data("next".utf8))
        await waitFor { recorder.count == 2 }
        #expect(recorder.count == 2)
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(recorder.requests.last?.httpBody == Data("next".utf8))
    }

    @Test func remoteTimeoutCancelsACooperativeTransport() async throws {
        let cancelled = Recorder()
        let sink = RemoteSink(url: URL(string: "http://localhost:18431/x")!, timeout: 0.1) { request in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if Task.isCancelled { await cancelled.record(request) {} }
        }
        sink.enqueue(Data("slow".utf8))
        await waitFor { cancelled.count == 1 }
        #expect(cancelled.count == 1)
    }

    @Test func remoteConfigurationIsValidated() {
        #expect(RemoteSink.collectorURL(server: "", token: "t") == nil)
        #expect(RemoteSink.collectorURL(server: "https://logs.example.com", token: "") == nil)
        #expect(RemoteSink.collectorURL(server: "logs.example.com", token: "t") == nil)
        #expect(RemoteSink.collectorURL(server: "https://logs.example.com/?k=v", token: "t") == nil)
        #expect(RemoteSink.collectorURL(server: "https://logs.example.com/#top", token: "t") == nil)
        #expect(RemoteSink.collectorURL(server: "https://logs.example.com/base", token: "t?x#y")?.absoluteString
                == "https://logs.example.com/base/api/v1/log/t%3Fx%23y")
        #expect(RemoteSink.sink(server: "", token: "t") == nil)
    }
}
