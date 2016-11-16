import XCTest
@testable import Perfect_Logger

class Perfect_LoggerTests: XCTestCase {
    func testBasic() {

		LogFile.critical("test critical default", "/Users/jonathanguthrie/Documents/Perfect-Collection/Perfect-Logger/test.log.txt")
    }


    static var allTests : [(String, (Perfect_LoggerTests) -> () throws -> Void)] {
        return [
            ("testBasic", testBasic),
        ]
    }
}
