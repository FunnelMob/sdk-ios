import XCTest
@testable import FunnelMob

final class EventValidationTests: XCTestCase {

    // MARK: - Valid Event Names

    func testValidEventName() {
        XCTAssertTrue(isValidEventName("purchase"))
        XCTAssertTrue(isValidEventName("button_click"))
        XCTAssertTrue(isValidEventName("level1Complete"))
        XCTAssertTrue(isValidEventName("step2_complete"))
        XCTAssertTrue(isValidEventName("a"))
        XCTAssertTrue(isValidEventName("fm_registration"))
    }

    // MARK: - Invalid Event Names

    func testEmptyEventName() {
        XCTAssertFalse(isValidEventName(""))
    }

    func testEventNameStartsWithNumber() {
        XCTAssertFalse(isValidEventName("2nd_purchase"))
        XCTAssertFalse(isValidEventName("123"))
    }

    func testEventNameWithSpecialChars() {
        XCTAssertFalse(isValidEventName("purchase-complete"))
        XCTAssertFalse(isValidEventName("purchase.complete"))
        XCTAssertFalse(isValidEventName("purchase@home"))
        XCTAssertFalse(isValidEventName("purchase#1"))
    }

    func testEventNameWithSpaces() {
        XCTAssertFalse(isValidEventName("purchase complete"))
        XCTAssertFalse(isValidEventName(" purchase"))
        XCTAssertFalse(isValidEventName("purchase "))
    }

    func testEventNameTooLong() {
        let longName = String(repeating: "a", count: 101)
        XCTAssertFalse(isValidEventName(longName))
    }

    func testEventNameMaxLength() {
        let maxName = String(repeating: "a", count: 100)
        XCTAssertTrue(isValidEventName(maxName))
    }

    // MARK: - Helper

    private func isValidEventName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        guard name.count <= 100 else { return false }

        let pattern = "^[a-zA-Z][a-zA-Z0-9_]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
