


#if os(Linux)
	import SwiftGlibc
	import LinuxBridge
#else
	import Darwin
#endif

import PerfectLib
import SwiftMoment

public var logFileLocation = "./log.txt"

struct FileLogger {
	let defaultFile = "./log.txt"
	let consoleEcho = ConsoleLogger()

	fileprivate init(){}

	func filelog(priority: String, _ args: String, _ logFile: String = logFileLocation) {
		let m = moment()
		var useFile = logFile
		if logFile.isEmpty { useFile = defaultFile }
		let ff = File(useFile)
		defer { ff.close() }
		do {
			try ff.open(.append)
			try ff.write(string: "\(priority) [\(m.format())] \(args)\n")
		} catch {
			consoleEcho.critical(message: "\(error)")
		}
	}

	func debug(message: String, _ logFile: String = logFileLocation) {
		consoleEcho.debug(message: message)
		filelog(priority: "[DEBUG]", message, logFile)
	}

	func info(message: String, _ logFile: String = logFileLocation) {
		consoleEcho.info(message: message)
		filelog(priority: "[INFO]", message, logFile)
	}

	func warning(message: String, _ logFile: String = logFileLocation) {
		consoleEcho.warning(message: message)
		filelog(priority: "[WARNING]", message, logFile)
	}

	func error(message: String, _ logFile: String = logFileLocation) {
		consoleEcho.error(message: message)
		filelog(priority: "[ERROR]", message, logFile)
	}

	func critical(message: String, _ logFile: String = logFileLocation) {
		consoleEcho.critical(message: message)
		filelog(priority: "[CRITICAL]", message, logFile)
	}

	func terminal(message: String, _ logFile: String = logFileLocation) {
		consoleEcho.terminal(message: message)
		filelog(priority: "[EMERG]", message, logFile)
	}
}

/// Placeholder functions for logging system
public struct LogFile {
	private init(){}

	static var logger = FileLogger()

	public static func debug(_ message: @autoclosure () -> String, _ logFile: String = logFileLocation) {
		//	#if DEBUG
		LogFile.logger.debug(message: message(), logFile)
		//	#endif
	}

	public static func info(_ message: String, _ logFile: String = logFileLocation) {
		LogFile.logger.info(message: message, logFile)
	}

	public static func warning(_ message: String, _ logFile: String = logFileLocation) {
		LogFile.logger.warning(message: message, logFile)
	}

	public static func error(_ message: String, _ logFile: String = logFileLocation) {
		LogFile.logger.error(message: message, logFile)
	}

	public static func critical(_ message: String, _ logFile: String = logFileLocation) {
		LogFile.logger.critical(message: message, logFile)
	}

	public static func terminal(_ message: String, _ logFile: String = logFileLocation) -> Never  {
		LogFile.logger.terminal(message: message, logFile)
		fatalError(message)
	}
}
