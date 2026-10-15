# Perfect Logging (File & Remote)

<p align="center">
    <img src="https://img.shields.io/badge/Swift-6.2%2B-orange.svg?style=flat" alt="Swift 6.2+">
    <img src="https://img.shields.io/badge/Platforms-macOS%2012%2B%20%7C%20Linux-lightgray.svg?style=flat" alt="Platforms macOS 12+ | Linux">
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

The pre-Swift-6 version (3.x) is preserved on the [`legacy`](../../tree/legacy) branch; see
[Migrating from 3.x](#migrating-from-3x).

## Requirements

- Swift 6.2 or later (`swift-tools-version: 6.2`, Swift 6 language mode).
- macOS 12 or later, or Linux. CI covers Swift 6.2 and 6.4 on Ubuntu 24.04 and Xcode 26.0.1
  and 26.6 on macOS, in debug and release, with warnings as errors.
- [`apple/swift-log`](https://github.com/apple/swift-log) 1.12.0 or later.

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
.package(url: "https://github.com/PerfectlySoft/Perfect-Logger.git", from: "4.0.0"),
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

Every argument is optional — pass only what you need. `remoteServer` needs a `remoteToken`; if
it is missing (or the server isn't an http(s) URL without a query or fragment) remote logging is
disabled with a warning on standard error. Likewise, a log file that can't be opened is reported
once on standard error and skipped. An optional `metadataProvider:` is installed as swift-log's global metadata provider and
merged into every handler's output.

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
re-bootstrapping, set `LogFile.logger` or `LogFile.logger.logLevel`. Each read and write of
`LogFile.logger` is thread-safe, but `LogFile.logger.logLevel = x` is a read followed by a write,
so racing it against `LogFile.logger = y` can lose one of the two.

`bootstrap` rebinds the default `LogFile.logger`, so `LogFile` calls made before bootstrapping
don't stick to swift-log's default backend. If you changed the default logger before
bootstrapping (say, `LogFile.logger.logLevel = .debug`), it is rebuilt on the new backend with the
same level and metadata. A logger with your own label is left alone.

`LogFile.terminal(_:)` logs at `.critical` with `perfect.priority=terminal` metadata, written as
`[EMERG]` by the file handler, and then aborts the process.

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
automatically). Timestamps use the `en_US_POSIX` locale and the Gregorian calendar in the
process's time zone, so the format doesn't change with the user's locale.

Other metadata — from the handler, its `metadataProvider`, the log call, or a logged `error:` —
is appended after the message as sorted `key=value` pairs when `.metadata` is in the options
(it is in `.default`). Lines whose only metadata is the event id look exactly as above:

```
[ERROR] [<eventid>] [2026-06-21 15:18:02 GMT-05:00] payment failed note="two words" order=1182 user=tim
```

Keys and values are escaped so metadata can't start a new line or blur a pair: `\`, `"`, newline,
carriage return and tab become `\\`, `\"`, `\n`, `\r` and `\t`, other control characters become
`\u{1b}` and so on, and anything empty or containing a space, `=` or `"` is double-quoted. Nested
dictionaries are written with sorted keys (`d="[a: 1, b: 2]"`). The message itself is written as is.

The file is opened in append mode and each line is a single write, so several processes can share
a log file and `logrotate`'s `copytruncate` works. A write that fails (for example on a full disk)
is dropped, and the handler tries to end a partly written line so the next one starts cleanly. A FIFO with no
reader, a directory or a socket is refused with a warning rather than blocking or failing later,
and a pipe whose reader goes away gives `EPIPE` rather than `SIGPIPE`. The handler can't protect
you from everything: exceeding `RLIMIT_FSIZE` still raises `SIGXFSZ`, and a write to a FIFO or
device that blocks blocks the logging thread.

## Remote logging

`RemoteLogHandler` POSTs each event to `<server>/api/v1/log/<token>` as JSON,
fire-and-forget (a failed POST never blocks or throws into the call site).
Wire it up via `bootstrap(remoteServer:remoteToken:)` above, or construct it
directly to combine with other handlers using swift-log's `MultiplexLogHandler`.

The body is an object with `level`, `label`, `source`, `eventid`, `message`, `timestamp`
(ISO 8601, UTC) and, when there is metadata besides the event id, `metadata` (string values).
Events are queued per collector and sent one at a time. Each POST gets at most 10 seconds,
however slowly the server answers; after that it's cancelled and the next event goes. At most
`RemoteLogHandler.maxPendingEvents` (1,000) wait; beyond that new events are dropped. Events still
queued when the process exits are lost.

The token is part of the URL path (as in 3.x), so use HTTPS and keep the collector's URL out of
access logs you don't control.

## Migrating from 3.x

4.0 is built on swift-log and drops the Perfect-CURL dependency. Most call sites keep compiling:
`LogFile.debug/info/warning/error/critical/terminal(_:eventid:)` still return the event id, and
`LogPriority` and `LogOptions` keep their cases.

- **Configure destinations once with `PerfectLogger.bootstrap(...)`** instead of setting
  `LogFile.location`, `LogFile.options`, `LogFile.even` and `LogFile.threshold`. Use
  `bootstrap(file:fileOptions:level:)`, or build a `FileLogHandler(label:path:options:even:)`.
- **The `logFile:` and `evenIdents:` arguments are gone** from the `LogFile` calls; one process
  logs to the destinations it bootstrapped.
- **`RemoteLogger` is replaced by `RemoteLogHandler`.** Pass `remoteServer:` and `remoteToken:` to
  `bootstrap`. The 3.x `[String: Any]` detail dictionaries become a message plus swift-log
  metadata. The endpoint is the same, but the JSON body is not: 3.x sent `appuuid`, `eventid`,
  `loglevel` and `detail`, so a collector written for 3.x needs to read the 4.0 fields above.
- **There is no separate console echo:** `bootstrap(console: true)` adds swift-log's stdout
  handler, whose format differs from 3.x's console lines.
- The file line format is the same as 3.x for events without extra metadata.

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Further Information

`PerfectLogger` is part of Tim Taplin's [Perfect-Resurrection](https://github.com/taplin/Perfect-Resurrection)
project, a Swift 6 rebuild of the original PerfectlySoft framework. Its only
current consumer is `PerfectTemplate`; see that repo for it in real use.
