import XCTest
@testable import StrataMonitorKit

final class JSONTests: XCTestCase {
    func testReadsNumbersInAnyForm() throws {
        let json = try JSON(data: Data("""
        {"a": 1, "b": 1.5, "c": "2", "d": true, "e": null, "f": [1, null, 3]}
        """.utf8))
        XCTAssertEqual(json["a"].int, 1)
        XCTAssertEqual(json["a"].double, 1)
        XCTAssertEqual(json["b"].double, 1.5)
        XCTAssertEqual(json["c"].double, 2)
        XCTAssertEqual(json["d"].bool, true)
        XCTAssertTrue(json["e"].isNull)
        XCTAssertEqual(json["f"].array.count, 3)
        XCTAssertEqual(json["f"].array[0].int, 1)
        XCTAssertNil(json["f"].array[1].double)
    }

    func testMissingKeysAreNil() throws {
        let json = try JSON(data: Data("{}".utf8))
        XCTAssertNil(json["нет"]["вложенного"].string)
        XCTAssertNil(json["нет"]["вложенного"].double)
        XCTAssertTrue(json["нет"].array.isEmpty)
    }
}
