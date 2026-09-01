# Perfect Logging (File & Remote)

<p align="center">
    <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B-lightgray.svg?style=flat" alt="Platforms macOS 12+">
    <a href="LICENSE" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg?style=flat" alt="License Apache 2.0">
    </a>
</p>

**Rebuilt on [`apple/swift-log`](https://github.com/apple/swift-log).** PerfectLogger provides a
friendly Perfect-style façade (`LogFile`) plus two custom `LogHandler` backends (`FileLogHandler`,
`RemoteLogHandler`) that bootstrap into the standard swift-log system. Libraries log against the
plain swift-log `Logger` and stay backend-agnostic; applications decide where logs go — to console,
file, and/or a remote collector.

Both targets build under full Swift 6 language mode with strict concurrency checking.

The pre-Swift-6 version is preserved on the [`legacy`](../../tree/legacy) branch.

## Where this fits

`PerfectLogger` is a leaf package — no dependency on any other package here, and currently only
**PerfectTemplate** depends on it directly (in four of its source files). Other packages in this
ecosystem (Perfect-Lasso, Perfect-NIO, etc.) deliberately log against raw swift-log (`import
Logging`) directly rather than through this façade. That's not a sign `PerfectLogger` is unused —
it's the intended integration point for applications that want the friendlier `LogFile` API and the
file/remote handlers, while libraries elsewhere stay backend-agnostic by talking to swift-log
directly.

## Using in your project

Add the dependency to your project's `Package.swift`:

``` swift
.package(url: "https://github.com/PerfectlySoft/Perfect-Logger.git", branch: "main"),
```

…and add `PerfectLogger` to your target's dependencies. Then import it:

``` swift
import PerfectLogger
```

## Building and testing this repo

``` shell
swift build
swift test
```

## Bootstrapping

Call `PerfectLogger.bootstrap(...)` once, early in app startup. It wires any
combination of console, file, and remote handlers into swift-log's global
`LoggingSystem` (which may only be bootstrapped a single time per process):

``` swift
PerfectLogger.bootstrap(
    console: true,                       // echo to stdout
    file: "/var/log/myapp.log",          // append structured lines to a file
    remoteServer: "https://logs.example.com",
    remoteToken: "<your token>",
    level: .info                         // minimum level for all handlers
)
```

Every argument except `console` is optional — pass only what you need.

## Friendly façade: `LogFile`

`LogFile` keeps the original ergonomic Perfect surface. Each call returns a
reusable **event id** so related events can be correlated:

``` swift
let eid = LogFile.warning("payment retry scheduled")
LogFile.critical("payment failed", eventid: eid)   // same id → linked events
```

With the file handler's default options the file receives:

```
[WARNING] [62f940aa-f204-43ed-9934-166896eda21c] [2026-06-21 15:18:02 GMT-05:00] payment retry scheduled
[CRITICAL] [62f940aa-f204-43ed-9934-166896eda21c] [2026-06-21 15:18:02 GMT-05:00] payment failed
```

The returned eventid is `@discardableResult`, so it can be ignored when not needed.

`LogFile` delegates to a swift-log `Logger`. To gate output or retarget it without
re-bootstrapping, set `LogFile.logger` or `LogFile.logger.logLevel`.

## Logging from a library (swift-log façade)

Libraries should log against a plain swift-log `Logger` and let the host app
choose the backend — no hard dependency on the file/remote handlers:

``` swift
import Logging

let logger = Logger(label: "com.example.MyLibrary")
logger.error("connection failed", metadata: ["eventid": "\(UUID().uuidString)"])
```

## File line format: `LogOptions`

`FileLogHandler` controls its prefix fields via `LogOptions`:

``` swift
FileLogHandler(label: "app", path: "/var/log/app.log", options: .default)
// "[ERROR] [<eventid>] [2026-06-21 15:18:02 GMT-05:00] message"

FileLogHandler(label: "app", path: "/var/log/app.log", options: .none)
// "message"

FileLogHandler(label: "app", path: "/var/log/app.log", options: [.priority, .timestamp])
// "[ERROR] [2026-06-21 15:18:02 GMT-05:00] message"
```

The event id is read from the `eventid` metadata key (which `LogFile` sets
automatically).

## Remote logging

`RemoteLogHandler` POSTs each event to `<server>/api/v1/log/<token>` as JSON,
fire-and-forget (a failed POST never blocks or throws into the call site).
Wire it up via `bootstrap(remoteServer:remoteToken:)` above, or construct it
directly to combine with other handlers using swift-log's `MultiplexLogHandler`.

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Further Information

`PerfectLogger` is part of Tim Taplin's [Perfect-Resurrection](https://github.com/taplin/Perfect-Resurrection)
project, a Swift 6 rebuild of the original PerfectlySoft framework. Its only
current consumer is `PerfectTemplate`; see that repo for it in real use.
