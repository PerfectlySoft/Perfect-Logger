//
//  RemoteLogger.swift
//  Perfect-Logger
//
//  Created by Jonathan Guthrie on 2017-01-09.
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


import PerfectLib
import SwiftMoment
import PerfectCURL
import cURL


public struct RemoteLogger {
	public static var logServer = "http://localhost:8100"
	public static var token = ""
	public static var appid = ""

	static let consoleEcho = ConsoleLogger()

	fileprivate init(){}

	static func log(priority: String, _ detail: [String:Any], _ eventid: String) throws {
		let useragent = "PerfectServer2.0"
		let logAPI = "/api/v1/log/"
		var obj = [String:Any]()
		obj["appuuid"] = RemoteLogger.appid
		obj["eventid"] = eventid
		obj["loglevel"] = priority
		obj["detail"] = detail
		var body = ""
		do {
			try body = obj.jsonEncodedString()
		} catch {
			throw error
		}

		var url = RemoteLogger.logServer + logAPI + RemoteLogger.token

		let curlObject = CURL(url: url)
		curlObject.setOption(CURLOPT_HTTPHEADER, s: "Accept: application/json")
		curlObject.setOption(CURLOPT_HTTPHEADER, s: "Cache-Control: no-cache")
		curlObject.setOption(CURLOPT_USERAGENT, s: useragent)


		if !body.isEmpty {
			let byteArray = [UInt8](body.utf8)
			curlObject.setOption(CURLOPT_POST, int: 1)
			curlObject.setOption(CURLOPT_POSTFIELDSIZE, int: byteArray.count)
			curlObject.setOption(CURLOPT_COPYPOSTFIELDS, v: UnsafeMutablePointer(mutating: byteArray))
			curlObject.setOption(CURLOPT_HTTPHEADER, s: "Content-Type: application/json")
		}



		var header = [UInt8]()
		var bodyIn = [UInt8]()

		var code = 0
		var data = [String: Any]()
		var raw = [String: Any]()

		var perf = curlObject.perform()
		defer { curlObject.close() }

		while perf.0 {
			if let h = perf.2 {
				header.append(contentsOf: h)
			}
			if let b = perf.3 {
				bodyIn.append(contentsOf: b)
			}
			perf = curlObject.perform()
		}
		if let h = perf.2 {
			header.append(contentsOf: h)
		}
		if let b = perf.3 {
			bodyIn.append(contentsOf: b)
		}
		let _ = perf.1

		// no need to parse. It's really just one way...

	}

	/// Logs a [DEBUG] message to the log server.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func debug(_ detail: [String:Any] = [String:Any](), eventid: String = UUID().string) -> String {
		do {
			consoleEcho.debug(message: try detail.jsonEncodedString())
			try RemoteLogger.log(priority: "debug", detail, eventid)
		} catch {
			consoleEcho.error(message: "\(error)")
		}
		return eventid
	}

	/// Logs a [INFO] message to the log server.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func info(_ detail: [String:Any] = [String:Any](), eventid: String = UUID().string) -> String {
		do {
			consoleEcho.info(message: try detail.jsonEncodedString())
			try RemoteLogger.log(priority: "info", detail, eventid)
		} catch {
			consoleEcho.error(message: "\(error)")
		}
		return eventid
	}

	/// Logs a [WARNING] message to the log server.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func warning(_ detail: [String:Any] = [String:Any](), eventid: String = UUID().string) -> String {
		do {
			consoleEcho.warning(message: try detail.jsonEncodedString())
			try RemoteLogger.log(priority: "warning", detail, eventid)
		} catch {
			consoleEcho.error(message: "\(error)")
		}
		return eventid
	}

	/// Logs a [ERROR] message to the log server.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func error(_ detail: [String:Any] = [String:Any](), eventid: String = UUID().string) -> String {
		do {
			consoleEcho.error(message: try detail.jsonEncodedString())
			try RemoteLogger.log(priority: "error", detail, eventid)
		} catch {
			consoleEcho.error(message: "\(error)")
		}
		return eventid
	}

	/// Logs a [CRIICAL] message to the log server.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	/// Returns an eventid string. If one was supplied, it will be echoed back, else a new one will be generated for reuse.
	@discardableResult
	public static func critical(_ detail: [String:Any] = [String:Any](), eventid: String = UUID().string) -> String {
		do {
			consoleEcho.critical(message: try detail.jsonEncodedString())
			try RemoteLogger.log(priority: "critical", detail, eventid)
		} catch {
			consoleEcho.error(message: "\(error)")
		}
		return eventid
	}

	/// Logs a [EMERG] message to the log server.
	/// Also echoes the message to the console.
	/// Specifiy a logFile parameter to direct the logging to a file other than the default.
	/// Takes an optional "eventid" param, which helps to link related events together.
	public static func terminal(_ detail: [String:Any] = [String:Any](), eventid: String = UUID().string) -> Never {
		do {
			consoleEcho.critical(message: try detail.jsonEncodedString())
			try RemoteLogger.log(priority: "emerg", detail, eventid)
			let str = try detail.jsonEncodedString()
			fatalError(str)
		} catch {
			fatalError("Unspecfified fatal error. Additionally the object failed to render as JSON.")
		}
	}
}

