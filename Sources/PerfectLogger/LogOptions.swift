//
//  LogOptions.swift
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

public struct LogOptions: OptionSet {
	/// Rawvalue of this option set
	public let rawValue: Int
	
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}
	
	/*
	* MARK: Default sets
	*/
	
	/// Default option set
	public static let `default`: LogOptions = [.priority, .eventId, .timestamp]
	
	/// Will only log the message itself
	public static let none: LogOptions = []
	
	/*
	* MARK: Options
	*/
	
	/// Logs the level/priority (e.g. "[DEBUG]")
	public static let priority  = LogOptions(rawValue: 1 << 0)
	
	/// Logs the event ID (e.g. "[34E621FD-9A57-47A0-BD3A-1B432B77BA30]")
	public static let eventId   = LogOptions(rawValue: 1 << 1)
	
	/// Logs the timestamp (e.g. "[2019-05-04 13:25:55 GMT+02:00]")
	public static let timestamp = LogOptions(rawValue: 1 << 2)
	
}
