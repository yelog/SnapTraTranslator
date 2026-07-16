import XCTest
@testable import SnapTra_Translator

final class SinglePressLookupRequestTests: XCTestCase {
    func testRequestKeepsTriggerPointWhenLaterPointChanges() {
        let triggerPoint = CGPoint(x: 120, y: 240)
        let request = makeRequest(mouseLocation: triggerPoint)
        let laterPoint = CGPoint(x: 800, y: 600)

        XCTAssertNotEqual(laterPoint, triggerPoint)
        XCTAssertEqual(request.mouseLocation, triggerPoint)
    }

    func testEachContinuousLookupCanFreezeItsOwnPoint() {
        let first = makeRequest(mouseLocation: CGPoint(x: 100, y: 200))
        let second = makeRequest(mouseLocation: CGPoint(x: 140, y: 260))

        XCTAssertNotEqual(first.lookupID, second.lookupID)
        XCTAssertEqual(first.mouseLocation, CGPoint(x: 100, y: 200))
        XCTAssertEqual(second.mouseLocation, CGPoint(x: 140, y: 260))
    }

    func testUnsupportedChannelUsesOCROnlyPolicy() {
        let request = makeRequest(supportsSelectedText: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testDisabledSelectedTextUsesOCROnlyPolicy() {
        let request = makeRequest(selectedTextEnabled: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testMissingAccessibilityUsesOCROnlyPolicy() {
        let request = makeRequest(hasAccessibilityPermission: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testSelectionFirstPolicyPreservesClipboardSetting() {
        XCTAssertEqual(
            makeRequest(clipboardFallbackEnabled: true).executionPolicy,
            .selectionFirst(allowsClipboardFallback: true)
        )
        XCTAssertEqual(
            makeRequest(clipboardFallbackEnabled: false).executionPolicy,
            .selectionFirst(allowsClipboardFallback: false)
        )
    }

    private func makeRequest(
        mouseLocation: CGPoint = CGPoint(x: 120, y: 240),
        supportsSelectedText: Bool = true,
        selectedTextEnabled: Bool = true,
        clipboardFallbackEnabled: Bool = true,
        hasAccessibilityPermission: Bool = true
    ) -> SinglePressLookupRequest {
        SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: mouseLocation,
            supportsSelectedText: supportsSelectedText,
            selectedTextEnabled: selectedTextEnabled,
            clipboardFallbackEnabled: clipboardFallbackEnabled,
            hasAccessibilityPermission: hasAccessibilityPermission
        )
    }
}
