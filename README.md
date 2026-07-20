# Perfect Logging (File & Remote)

<p align="center">
    <img src="https://img.shields.io/badge/Swift-6.2-orange.svg?style=flat" alt="Swift 6.2">
    <img src="https://img.shields.io/badge/Platforms-macOS%2026%2B-lightgray.svg?style=flat" alt="Platforms macOS 26+">
    <a href="LICENSE" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache%202.0-lightgrey.svg?style=flat" alt="License Apache 2.0">
    </a>
</p>

> **Swift 6 resurrection note.** This package has been rebuilt on top of
> [`apple/swift-log`](https://github.com/apple/swift-log). PerfectLogger now provides a
> friendly Perfect-style façade (`LogFile`) plus two custom `LogHandler` backends
> (`FileLogHandler`, `RemoteLogHandler`) that you bootstrap into the standard
> swift-log system. Libraries can log against the plain swift-log `Logger`
> façade and stay backend-agnostic; applications decide where the logs go.
>
> Both targets build under full Swift 6 language mode (`swiftSettings:
> [.swiftLanguageMode(.v6)]`, strict concurrency checking on) and implement
> swift-log's current, non-deprecated `LogHandler` requirement — this is a
> small, modern, actively-buildable package, not a leftover from the original
> pre-resurrection codebase.

Using the `PerfectLogger` module, events can be logged to the console, to a file,
and/or shipped to a remote collector — all through swift-log's `LogHandler` system.

**Requires Swift 6.2 and macOS 26+** (per `Package.swift`; no Linux or iOS
target is currently declared).

## Where this fits in Perfect-Resurrection

`PerfectLogger` is a leaf package in the [Perfect-Resurrection](https://github.com/taplin/Perfect-Resurrection)
ecosystem — it has no dependency on any other Perfect-Resurrection package, and
nothing in the graph depends on it except **PerfectTemplate**, which imports it
in four of its source files today. Other core packages in the ecosystem
(Perfect-Lasso, Perfect-NIO, etc.) deliberately log against raw swift-log
(`import Logging`) directly rather than through this façade. That's not a sign
`PerfectLogger` is unused or abandoned — it's the intended integration point
for applications (like PerfectTemplate) that want the friendlier `LogFile`
API and the file/remote handlers, while libraries elsewhere in the ecosystem
stay backend-agnostic by talking to swift-log directly.

## Using in your project

Add the dependency to your project's `Package.swift`:

``` swift
.package(url: "https://github.com/taplin/Perfect-Logger.git", from: "3.3.0"),
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
