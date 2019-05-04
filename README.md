# Perfect Logging (File & Remote)

<p align="center">
    <a href="http://perfect.org/get-involved.html" target="_blank">
        <img src="http://perfect.org/assets/github/perfect_github_2_0_0.jpg" alt="Get Involed with Perfect!" width="854" />
    </a>
</p>

<p align="center">
    <a href="https://github.com/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg" alt="Star Perfect On Github" />
    </a>  
    <a href="http://stackoverflow.com/questions/tagged/perfect" target="_blank">
        <img src="http://www.perfect.org/github/perfect_gh_button_2_SO.jpg" alt="Stack Overflow" />
    </a>  
    <a href="https://twitter.com/perfectlysoft" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_3_twit.jpg" alt="Follow Perfect on Twitter" />
    </a>  
    <a href="http://perfect.ly" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_4_slack.jpg" alt="Join the Perfect Slack" />
    </a>
</p>

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-3.0-orange.svg?style=flat" alt="Swift 3.0">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-OS%20X%20%7C%20Linux%20-lightgray.svg?style=flat" alt="Platforms OS X | Linux">
    </a>
    <a href="http://perfect.org/licensing.html" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
    <a href="http://twitter.com/PerfectlySoft" target="_blank">
        <img src="https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat" alt="PerfectlySoft Twitter">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>

Using the `PerfectLogger` module, events can be logged to a specfied file, in addition to the console.

Support is also included in this module for remote logging events to the [Perfect Log Server](https://github.com/PerfectServers/Perfect-LogServer).

## Using in your project

Add the dependancy to your project's Package.swift file:

``` swift
.Package(url: "https://github.com/PerfectlySoft/Perfect-Logger.git", majorVersion: 3),
```

Now add the `import` directive to the file you wish to use the logging in:

``` swift
import PerfectLogger
```

To log events to the local console as well as a file:

``` swift
LogFile.debug("debug message", logFile: "test.txt")
LogFile.info("info message", logFile: "test.txt")
LogFile.warning("warning message", logFile: "test.txt")
LogFile.error("error message", logFile: "test.txt")
LogFile.critical("critical message", logFile: "test.txt")
LogFile.terminal("terminal message", logFile: "test.txt")
```

To log to the default file, omit the file name parameter.

## Linking events with "eventid"

Each log event returns an event id string. If an eventid string is supplied to the directive then it will use the supplied eventid in the log file instead - this makes it easy to link together related events.

``` swift
let eid = LogFile.warning("test 1")
LogFile.critical("test 2", eventid: eid)
```

returns:

```
[WARNING] [62f940aa-f204-43ed-9934-166896eda21c] [2016-11-16 15:18:02 GMT-05:00] test 1
[CRITICAL] [62f940aa-f204-43ed-9934-166896eda21c] [2016-11-16 15:18:02 GMT-05:00] test 2
```

The returned eventid is marked `@discardableResult` therefore can be safely ignored if not required for re-use.


## Customization

### Setting a custom Logfile location

The default logfile location is `./log.log`. To set a custom logfile location, set the `LogFile.location` variable:

``` swift
LogFile.location = "/var/log/myLog.log"
```

Messages can now be logged directly to the file as set by using:

``` swift
LogFile.debug("debug message")
LogFile.info("info message")
LogFile.warning("warning message")
LogFile.error("error message")
LogFile.critical("critical message")
LogFile.terminal("terminal message")
```

### LogFile threshold

For debug purposes, you want to see as much info as available. However, on production servers you probably desire a
smaller logfile and filter out all redundant info.

To do so, you may set the LogFile's `threshold` property to the minumum priority you want to actually being logged into the file.

e.g.:

```swift
LogFile.threshold = .warning
LogFile.debug("This won't be logged into the file")
LogFile.info("This won't be logged into the file")
LogFile.warning("This will be logged into the file")
LogFile.error("This will be logged into the file")
LogFile.critical("This will be logged into the file")
```

The default value of this property is `.debug` to preserve backward compatibility and this property will not affect the Console/Remote logger.

### LogFile options

Depending on your needs, you may not be interested in an event id, timestamp or priority.

Using the LogFile's `options` property you can customize which of those fields will actually be added as a prefix to the log message.

e.g.:

```swift
// Default behaviour (equal to `[.priority, .eventId, .timestamp]`)
LogFile.options = .default
LogFile.debug("This is my log message")
// Will log: "[DEBUG] [CEC5B5DB-931F-4C5A-A794-17D060BABC80] [2019-05-04 15:16:11 GMT+02:00] This is my log message"

LogFile.options = .none
LogFile.debug("This is my log message")
// Will log: "This is my log message"

LogFile.options = [.priority, .timestamp]
LogFile.debug("This is my log message")
// Will log: "[DEBUG] [2019-05-04 15:16:11 GMT+02:00] This is my log message"

LogFile.options = [.priority]
LogFile.debug("This is my log message")
// Will log: "[DEBUG] This is my log message"
```


## Sample output

```
[DEBUG] [ec6a9ca5-00b1-4656-9e4c-ddecae8dde02] [2016-11-16 15:18:02 GMT-05:00] a debug message
[INFO] [ec6a9ca5-00b1-4656-9e4c-ddecae8dde02] [2016-11-16 15:18:02 GMT-05:00] an informational message
[WARNING] [ec6a9ca5-00b1-4656-9e4c-ddecae8dde02] [2016-11-16 15:18:02 GMT-05:00] a warning message
[ERROR] [62f940aa-f204-43ed-9934-166896eda21c] [2016-11-16 15:18:02 GMT-05:00] an error message
[CRITICAL] [62f940aa-f204-43ed-9934-166896eda21c] [2016-11-16 15:18:02 GMT-05:00] a critical message
[EMERG] [ec6a9ca5-00b1-4656-9e4c-ddecae8dde02] [2016-11-16 15:18:02 GMT-05:00] an emergency message
```

## Remote Logging

The "Perfect-Logging" dependency includes support for remote logging to this log server.

To include the dependency in your project, add the following to your project's Package.swift file:

``` swift
.Package(url: "https://github.com/PerfectlySoft/Perfect-Logger.git", majorVersion: 3),
```

Now add the import directive to the file you wish to use the logging in:

``` swift 
import PerfectLogger
```

#### Configuration
Three configuration parameters are required:

``` swift
// Your token
RemoteLogger.token = "<your token>"

// App ID (Optional)
RemoteLogger.appid = "<your appid>"

// URL to access the log server. 
// Note, this is not the full API path, just the host and port.
RemoteLogger.logServer = "http://localhost:8181"

```


#### To log events to the log server:

``` swift
var obj = [String: Any]()
obj["one"] = "donkey"
RemoteLogger.critical(obj)
```

#### Linking events with "eventid"

Each log event returns an event id string. If an eventid string is supplied to the directive then it will use the supplied eventid in the log directive instead - this makes it easy to link together related events.

``` swift
let eid = RemoteLogger.critical(obj)
RemoteLogger.info(obj, eventid: eid)
```

The returned eventid is marked @discardableResult therefore can be safely ignored if not required for re-use.

## Further Information
For more information on the Perfect project, please visit [perfect.org](http://perfect.org).
