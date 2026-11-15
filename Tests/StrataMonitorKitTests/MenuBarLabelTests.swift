import XCTest
@testable import StrataMonitorKit

final class MenuBarLabelTests: XCTestCase {
    func testNumberTextFitsIntoTheSlot() {
        // Всё, что помещается в слот из четырёх знаков, показывается как есть.
        XCTAssertEqual(MenuBarLabel.numberText(0), "0")
        XCTAssertEqual(MenuBarLabel.numberText(5), "5")
        XCTAssertEqual(MenuBarLabel.numberText(99), "99")
        XCTAssertEqual(MenuBarLabel.numberText(140), "140")
        XCTAssertEqual(MenuBarLabel.numberText(1234), "1234")
    }

    func testBigNumbersAreCompacted() {
        XCTAssertEqual(MenuBarLabel.numberText(12_345), "12k")
        XCTAssertEqual(MenuBarLabel.numberText(123_456), "123k")
        XCTAssertEqual(MenuBarLabel.numberText(999_999), "999k")
        XCTAssertEqual(MenuBarLabel.numberText(1_000_000), "1M")
    }

    func testSlotIsNeverWiderThanReserved() {
        for tps in [0.0, 7, 42, 140, 1234, 9999, 12_345, 999_999] {
            XCTAssertLessThanOrEqual(MenuBarLabel.numberText(tps).count, MenuBarLabel.numberSlots,
                                     "число \(tps) не влезает в слот")
        }
    }

    func testEmptySlotShowsDashes() {
        XCTAssertEqual(MenuBarLabel.slotText(nil), "--")
        XCTAssertEqual(MenuBarLabel.slotText(140), "140")
    }
}
