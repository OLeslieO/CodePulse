import XCTest
import Foundation
import SignalCore

final class UsageTests: XCTestCase {
    func mapping() -> UsageMapping {
        var mapping = UsageMapping(); mapping.endpoint = "https://example.com/balance"
        mapping.balancePath = "data.balance"; mapping.usedPath = "data.used"
        mapping.limitPath = "data.limit"; mapping.unit = "credits"; mapping.periodLabel = "本月"; mapping.scale = "100"
        return mapping
    }
    func testPrecisionAndOverage() throws {
        let data = Data(#"{"data":{"balance":"10001","used":15000,"limit":10000}}"#.utf8)
        let result = try UsageSnapshot.parse(data, mapping: mapping())
        XCTAssertEqual(result.balance, Decimal(string: "100.01"))
        XCTAssertEqual(result.ratio, Decimal(string: "1.5"))
    }
    func testMissingAndInvalidAmountsFailRatherThanZero() {
        for json in [#"{"data":{}}"#, #"{"data":{"balance":true,"used":1,"limit":2}}"#,
                     #"{"data":{"balance":"12foo","used":1,"limit":2}}"#,
                     #"{"data":{"balance":0,"used":-1,"limit":2}}"#] {
            XCTAssertThrowsError(try UsageSnapshot.parse(Data(json.utf8), mapping: mapping()))
        }
    }
    func testNullLimitHasNoFakePercentage() throws {
        let result = try UsageSnapshot.parse(Data(#"{"data":{"balance":0,"used":1,"limit":null}}"#.utf8), mapping: mapping())
        XCTAssertNil(result.ratio); XCTAssertEqual(result.balance, 0)
    }
    func testRejectCredentialsInURLAndInvalidMapping() {
        for endpoint in ["http://example.com", "https://secret@example.com", "https://example.com?key=secret"] {
            var config = mapping(); config.endpoint = endpoint
            XCTAssertThrowsError(try config.validatedURL())
        }
        var config = mapping(); config.scale = "0"; XCTAssertThrowsError(try config.validatedURL())
        config = mapping(); config.periodLabel = ""; XCTAssertThrowsError(try config.validatedURL())
    }
}
