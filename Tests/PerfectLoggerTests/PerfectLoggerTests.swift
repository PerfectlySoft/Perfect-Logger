import XCTest
@testable import PerfectLogger

class PerfectLoggerTests: XCTestCase {
	func testBasic() {
		LogFile.location = "./test_set.txt"
		LogFile.critical("test critical default", logFile:"./test_log.txt")
		let eid = LogFile.critical("test critical default file")
		LogFile.critical("test critical default file 1")
		LogFile.critical("test critical default file 2", eventid: eid)
	}

	func testRemote() {
		RemoteLogger.token = "eecb34a4-4c1c-43ed-af24-3bed830a3112"
		RemoteLogger.appid = "59b4a4b8-fd5e-45b1-b8ed-48bcab82049f"
		RemoteLogger.logServer = "http://localhost:8181"

		var obj = [String: Any]()
		obj["one"] = "donkey"

		RemoteLogger.critical(obj)

		obj["two"] = "hares"
		let eid = RemoteLogger.critical(obj)

		obj["three"] = "hippo"

		RemoteLogger.info(obj)

		obj["four"] = "tigers"
		RemoteLogger.critical(obj, eventid: eid)
	}



    static var allTests : [(String, (PerfectLoggerTests) -> () throws -> Void)] {
        return [
            ("testBasic", testBasic),
        ]
    }
}
