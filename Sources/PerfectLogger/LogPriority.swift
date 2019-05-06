//
//  LogPriority.swift
//  PerfectLogger
//
//  Created by Michiel Horvers on 04/05/2019.
//    Copyright (C) 2019 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2019 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//


import Foundation

/**
Priority of the message.

Either one of:
* debug
* info
* warning
* error
* critical
* terminal

*/
public enum LogPriority: Int {
	case debug
	case info
	case warning
	case error
	case critical
	case terminal
}

internal extension LogPriority {
	/**
	Returns the string representation for this level.
	
	If `even` set to true,  log messages will be inline with each other
	
	- parameter even: Whether or not to even off the log messages
	
	- returns: The string representation for this log level
	*/
	func stringRepresentation(even: Bool) -> String {
		switch self {
		case .debug:    return "[DEBUG]"
		case .info:     return even ? "[INFO] " : "[INFO]"
		case .warning:  return even ? "[WARN] " : "[WARNING]"
		case .error:    return "[ERROR]"
		case .critical: return even ? "[CRIT] " : "[CRITICAL]"
		case .terminal: return even ? "[EMERG]" : "[EMERG]"
		}
	}
}

extension LogPriority: Comparable {
	public static func >(lhs: LogPriority, rhs: LogPriority) -> Bool {
		return lhs.rawValue > rhs.rawValue
	}
	
	public static func <(lhs: LogPriority, rhs: LogPriority) -> Bool {
		return lhs.rawValue < rhs.rawValue
	}
}
