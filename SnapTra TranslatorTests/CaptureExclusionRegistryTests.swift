import XCTest
@testable import SnapTra_Translator

final class CaptureExclusionRegistryTests: XCTestCase {
    func testExcludedWindowNumbersIncludeOnlyRegisteredVisibleWindows() {
        let excluded = CaptureExclusionRegistry.excludedWindowNumbers(
            registeredWindowNumbers: [101, 303],
            visibleWindowNumbers: [101, 202, 303, 404]
        )

        XCTAssertEqual(excluded, [101, 303])
    }

    func testExcludedWindowNumbersDoNotExcludeUnregisteredSameAppWindows() {
        let settingsWindowNumber = 202

        let excluded = CaptureExclusionRegistry.excludedWindowNumbers(
            registeredWindowNumbers: [101],
            visibleWindowNumbers: [101, settingsWindowNumber]
        )

        XCTAssertEqual(excluded, [101])
        XCTAssertFalse(excluded.contains(settingsWindowNumber))
    }

    func testExcludedWindowNumbersAreEmptyWhenNoOverlayWindowsAreRegistered() {
        let excluded = CaptureExclusionRegistry.excludedWindowNumbers(
            registeredWindowNumbers: [],
            visibleWindowNumbers: [101, 202]
        )

        XCTAssertTrue(excluded.isEmpty)
    }
}
