import XCTest
@testable import PerfectLogger

class PerfectLoggerTests: XCTestCase {
    func testBasic() {

		LogFile.location = "/Users/jonathanguthrie/Documents/Perfect-Collection/Perfect-Logger/test.set.txt"

		LogFile.critical("test critical default", logFile:"/Users/jonathanguthrie/Documents/Perfect-Collection/Perfect-Logger/test.log.txt")
		let eid = LogFile.critical("test critical default file")
		LogFile.critical("test critical default file 1")
		LogFile.critical("test critical default file 2", eventid: eid)
    }


    static var allTests : [(String, (PerfectLoggerTests) -> () throws -> Void)] {
        return [
            ("testBasic", testBasic),
        ]
    }
}
