import XCTest
@testable import PerfectLogger

class PerfectLoggerTests: XCTestCase {
    func testBasic() {

		LogFile.critical("test critical default", "/Users/jonathanguthrie/Documents/Perfect-Collection/Perfect-Logger/test.log.txt")
    }


    static var allTests : [(String, (PerfectLoggerTests) -> () throws -> Void)] {
        return [
            ("testBasic", testBasic),
        ]
    }
}
