import XCTest
@testable import CoParentingApp

final class SlotUtilityTests: XCTestCase {

    // MARK: - slot(hour:minute:) Tests

    func testSlotMidnight() {
        XCTAssertEqual(SlotUtility.slot(hour: 0, minute: 0), 0)
    }

    func testSlot8AM() {
        XCTAssertEqual(SlotUtility.slot(hour: 8, minute: 0), 32)
    }

    func testSlotNoon() {
        XCTAssertEqual(SlotUtility.slot(hour: 12, minute: 0), 48)
    }

    func testSlot6PM() {
        XCTAssertEqual(SlotUtility.slot(hour: 18, minute: 0), 72)
    }

    func testSlot7AM() {
        XCTAssertEqual(SlotUtility.slot(hour: 7, minute: 0), 28)
    }

    func testSlot730AM() {
        XCTAssertEqual(SlotUtility.slot(hour: 7, minute: 30), 30)
    }

    func testSlot730PM() {
        XCTAssertEqual(SlotUtility.slot(hour: 19, minute: 30), 78)
    }

    func testSlot815AM() {
        // 8:15 AM -> 8*4 + 15/15 = 33
        XCTAssertEqual(SlotUtility.slot(hour: 8, minute: 15), 33)
    }

    func testSlot345PM() {
        // 15:45 -> 15*4 + 45/15 = 63
        XCTAssertEqual(SlotUtility.slot(hour: 15, minute: 45), 63)
    }

    // MARK: - time(for:) Tests

    func testTimeForSlot0() {
        let (hour, minute) = SlotUtility.time(for: 0)
        XCTAssertEqual(hour, 0)
        XCTAssertEqual(minute, 0)
    }

    func testTimeForSlot32() {
        let (hour, minute) = SlotUtility.time(for: 32)
        XCTAssertEqual(hour, 8)
        XCTAssertEqual(minute, 0)
    }

    func testTimeForSlot33() {
        let (hour, minute) = SlotUtility.time(for: 33)
        XCTAssertEqual(hour, 8)
        XCTAssertEqual(minute, 15)
    }

    func testTimeForSlot78() {
        let (hour, minute) = SlotUtility.time(for: 78)
        XCTAssertEqual(hour, 19)
        XCTAssertEqual(minute, 30)
    }

    func testTimeForSlot96() {
        let (hour, minute) = SlotUtility.time(for: 96)
        XCTAssertEqual(hour, 24)
        XCTAssertEqual(minute, 0)
    }

    // MARK: - formatSlot Tests

    func testFormatSlotMidnight() {
        let formatted = SlotUtility.formatSlot(0)
        XCTAssertTrue(formatted.contains("12") || formatted.contains("0"), "Midnight should contain '12' or '0': \(formatted)")
    }

    func testFormatSlot32() {
        let formatted = SlotUtility.formatSlot(32)
        XCTAssertTrue(formatted.contains("8"), "8 AM should contain '8': \(formatted)")
    }

    // MARK: - Validation Tests

    func testIsValidSlot() {
        XCTAssertTrue(SlotUtility.isValidSlot(0))
        XCTAssertTrue(SlotUtility.isValidSlot(48))
        XCTAssertTrue(SlotUtility.isValidSlot(96))
        XCTAssertFalse(SlotUtility.isValidSlot(-1))
        XCTAssertFalse(SlotUtility.isValidSlot(97))
    }

    func testIsValidRange() {
        XCTAssertTrue(SlotUtility.isValidRange(start: 0, end: 96))
        XCTAssertTrue(SlotUtility.isValidRange(start: 32, end: 48))
        XCTAssertFalse(SlotUtility.isValidRange(start: 48, end: 32))
        XCTAssertFalse(SlotUtility.isValidRange(start: 32, end: 32))
        XCTAssertFalse(SlotUtility.isValidRange(start: -1, end: 48))
    }

    // MARK: - Duration Tests

    func testDurationMinutes() {
        // 8 AM to noon = 4 hours = 240 min
        XCTAssertEqual(SlotUtility.durationMinutes(start: 32, end: 48), 240)
    }

    func testDurationHours() {
        XCTAssertEqual(SlotUtility.durationHours(start: 32, end: 48), 4.0)
        XCTAssertEqual(SlotUtility.durationHours(start: 28, end: 78), 12.5)
    }

    // MARK: - Common Constants

    func testCommonConstants() {
        XCTAssertEqual(SlotUtility.midnight, 0)
        XCTAssertEqual(SlotUtility.sixAM, 24)
        XCTAssertEqual(SlotUtility.eightAM, 32)
        XCTAssertEqual(SlotUtility.nineAM, 36)
        XCTAssertEqual(SlotUtility.noon, 48)
        XCTAssertEqual(SlotUtility.threePM, 60)
        XCTAssertEqual(SlotUtility.fivePM, 68)
        XCTAssertEqual(SlotUtility.sixPM, 72)
        XCTAssertEqual(SlotUtility.eightPM, 80)
        XCTAssertEqual(SlotUtility.ninePM, 84)
        XCTAssertEqual(SlotUtility.endOfDay, 96)
    }
}
