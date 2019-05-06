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
import Foundation

struct FileLogger {
	var threshold: LogPriority = .debug
	var options: LogOptions = .default
	
	let defaultFile = "./log.log"
	let consoleEcho = ConsoleLogger()
	let fmt = DateFormatter()
	fileprivate init(){
		fmt.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
	}
	
	func filelog(priority: LogPriority, _ args: String, _ eventid: String, _ logFile: String, _ even: Bool) {
		// Validate level threshold first
		guard priority >= threshold else { return }
		
		var prefixList = [String]()
		
		if options.contains(.priority) {
			prefixList.append(priority.stringRepresentation(even: even))
		}
		if options.contains(.eventId) {
			prefixList.append("[\(eventid)]")
		}
		if options.contains(.timestamp) {
			prefixList.append("[\(fmt.string(from: Date()))]")
		}
		
		// Add a space to seperate the prefix list from the message when the list contains at least 1 value
		let prefix = prefixList.count > 0 ? "\(prefixList.joined(separator: " ")) " : ""
		
		var useFile = logFile
		if logFile.isEmpty { useFile = defaultFile }
		let ff = File(useFile)
		defer { ff.close() }
		do {
			try ff.open(.append)
			try ff.write(string: "\(prefix)\(args)\n")
		} catch {
			consoleEcho.critical(message: "\(error)", even)
		}
	}
	
	func debug(message: String, _ eventid: String, _ logFile: String, _ even: Bool) {
		consoleEcho.debug(message: message, even)
		filelog(priority: .debug, message, eventid, logFile, even)
	}
	
	func info(message: String, _ eventid: String, _ logFile: String, _ even: Bool) {
		consoleEcho.info(message: message, even)
		filelog(priority: .info, message, eventid, logFile, even)
	}
	
	func warning(message: String, _ eventid: String, _ logFile: String, _ even: Bool) {
		consoleEcho.warning(message: message, even)
		filelog(priority: .warning, message, eventid, logFile, even)
	}
	
	func error(message: String, _ eventid: String, _ logFile: String, _ even: Bool) {
		consoleEcho.error(message: message, even)
		filelog(priority: .error, message, eventid, logFile, even)
	}
	
	func critical(message: String, _ eventid: String, _ logFile: String, _ even: Bool) {
		consoleEcho.critical(message: message, even)
		filelog(priority: .critical, message, eventid, logFile, even)
	}
	
	func terminal(message: String, _ eventid: String, _ logFile: String, _ even: Bool) {
		consoleEcho.terminal(message: message, even)
		filelog(priority: .terminal, message, eventid, logFile, even)
	}
}

/// Provision for logging information to a log file
public struct LogFile {
	private init(){}
	
	static var logger = FileLogger()
	
	/**
	Threshold for priorties to log
	
	e.g. when set to `.error` only error, critical and terminal messages will actually be logged
	*/
	public static var threshold: LogPriority {
		get {
			return logger.threshold
		}
		set {
			logger.threshold = newValue
		}
	}
	
	/**
	Log options that indicate which fields (e.g. priority, event ID) should be send to the log file.
	
	To use the default set:
	
	```
	LogFile.options = .default
	```
	
	To use a custom set:
	
	```
	LogFile.options = [.level, .timestamp]
	```
	*/
	public static var options: LogOptions {
		get {
			return logger.options
		}
		set {
			logger.options = newValue
		}
	}
	
	/// The location of the log file.
	/// The default location is relative, "log.log"
	public static var location = "./log.log"
	
	/// Whether or not to even off the log messages
	/// If set to true log messages will be inline with each other
	public static var even = false
	
	/// Logs a [DEBUG] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func debug(_ message: @autoclosure () -> String, eventid: String = Foundation.UUID().uuidString, logFile: String = location, evenIdents: Bool = even) -> String {
		LogFile.logger.debug(message: message(), eventid, logFile, evenIdents)
		return eventid
	}
	
	/// Logs a [INFO] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func info(_ message: String, eventid: String = Foundation.UUID().uuidString, logFile: String = location, evenIdents: Bool = even) -> String {
		LogFile.logger.info(message: message, eventid, logFile, evenIdents)
		return eventid
	}
	
	/// Logs a [WARNING] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func warning(_ message: String, eventid: String = Foundation.UUID().uuidString, logFile: String = location, evenIdents: Bool = even) -> String {
		LogFile.logger.warning(message: message, eventid, logFile, evenIdents)
		return eventid
	}
	
	/// Logs a [ERROR] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func error(_ message: String, eventid: String = Foundation.UUID().uuidString, logFile: String = location, evenIdents: Bool = even) -> String {
		LogFile.logger.error(message: message, eventid, logFile, evenIdents)
		return eventid
	}
	
	/// Logs a [CRIICAL] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func critical(_ message: String, eventid: String = Foundation.UUID().uuidString, logFile: String = location, evenIdents: Bool = even) -> String {
		LogFile.logger.critical(message: message, eventid, logFile, evenIdents)
		return eventid
	}
	
	/// Logs a [EMERG] message to the log file.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	public static func terminal(_ message: String, eventid: String = Foundation.UUID().uuidString, logFile: String = location, evenIdents: Bool = even) -> Never  {
		LogFile.logger.terminal(message: message, eventid, logFile, evenIdents)
		fatalError(message)
	}
}
