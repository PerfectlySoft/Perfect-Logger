// swift-tools-version:4.2
// Generated automatically by Perfect Assistant Application
// Date: 2017-09-29 18:02:27 +0000
import PackageDescription
let package = Package(
	name: "PerfectLogger",
	products: [
		.library(name: "PerfectLogger", targets: ["PerfectLogger"])
	],
	dependencies: [
		.package(url: "https://github.com/PerfectlySoft/Perfect-CURL.git", from: "3.0.0"),
	],
	targets: [
		.target(name: "PerfectLogger", dependencies: ["PerfectCURL"])
	]
)
