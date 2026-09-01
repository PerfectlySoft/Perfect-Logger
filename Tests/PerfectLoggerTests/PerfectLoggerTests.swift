import Testing
import Foundation
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
}
