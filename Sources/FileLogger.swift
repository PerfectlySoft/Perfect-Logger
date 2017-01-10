//
//  Perfect_Logger.swift
//  PerfectLogger
//
//  Created by Jonathan Guthrie on 16/11/2016.
//	Copyright (C) 2015 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//


#if os(Linux)
	import SwiftGlibc
	import LinuxBridge
#else
	import Darwin
#endif

import PerfectLib
import SwiftMoment

struct FileLogger {
	let defaultFile = "./log.log"
	let consoleEcho = ConsoleLogger()

	fileprivate init(){}

	func filelog(priority: String, _ args: String, _ eventid: String, _ logFile: String) {
		let m = moment()
		var useFile = logFile
		if logFile.isEmpty { useFile = defaultFile }
		let ff = File(useFile)
		defer { ff.close() }
		do {
			try ff.open(.append)
			try ff.write(string: "\(priority) [\(eventid)] [\(m.format())] \(args)\n")
		} catch {
			consoleEcho.critical(message: "\(error)")
		}
	}

	func debug(message: String, _ eventid: String, _ logFile: String) {
		consoleEcho.debug(message: message)
		filelog(priority: "[DEBUG]", message, eventid, logFile)
	}

	func info(message: String, _ eventid: String, _ logFile: String) {
		consoleEcho.info(message: message)
		filelog(priority: "[INFO]", message, eventid, logFile)
	}

	func warning(message: String, _ eventid: String, _ logFile: String) {
		consoleEcho.warning(message: message)
		filelog(priority: "[WARNING]", message, eventid, logFile)
	}

	func error(message: String, _ eventid: String, _ logFile: String) {
		consoleEcho.error(message: message)
		filelog(priority: "[ERROR]", message, eventid, logFile)
	}

	func critical(message: String, _ eventid: String, _ logFile: String) {
		consoleEcho.critical(message: message)
		filelog(priority: "[CRITICAL]", message, eventid, logFile)
	}

	func terminal(message: String, _ eventid: String, _ logFile: String) {
		consoleEcho.terminal(message: message)
		filelog(priority: "[EMERG]", message, eventid, logFile)
	}
}

/// Provision for logging information to a log file
public struct LogFile {
	private init(){}

	static var logger = FileLogger()

	/// The location of the log file.
	/// The default location is relative, "log.log"
	public static var location = "./log.log"

	/// Logs a [DEBUG] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func debug(_ message: @autoclosure () -> String, eventid: String = UUID().string, logFile: String = location) -> String {
		LogFile.logger.debug(message: message(), eventid, logFile)
		return eventid
	}

	/// Logs a [INFO] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func info(_ message: String, eventid: String = UUID().string, logFile: String = location) -> String {
		LogFile.logger.info(message: message, eventid, logFile)
		return eventid
	}

	/// Logs a [WARNING] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func warning(_ message: String, eventid: String = UUID().string, logFile: String = location) -> String {
		LogFile.logger.warning(message: message, eventid, logFile)
		return eventid
	}

	/// Logs a [ERROR] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func error(_ message: String, eventid: String = UUID().string, logFile: String = location) -> String {
		LogFile.logger.error(message: message, eventid, logFile)
		return eventid
	}

	/// Logs a [CRIICAL] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func critical(_ message: String, eventid: String = UUID().string, logFile: String = location) -> String {
		LogFile.logger.critical(message: message, eventid, logFile)
		return eventid
	}

	/// Logs a [EMERG] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	public static func terminal(_ message: String, eventid: String = UUID().string, logFile: String = location) -> Never  {
		LogFile.logger.terminal(message: message, eventid, logFile)
		fatalError(message)
	}
}
