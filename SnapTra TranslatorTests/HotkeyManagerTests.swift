import XCTest
@testable import SnapTra_Translator

final class HotkeyManagerTests: XCTestCase {
    func testFirstPressTriggersImmediately() {
        var stateMachine = HotkeyGestureStateMachine()

        let events = stateMachine.handlePress(now: Date())

        XCTAssertEqual(events, [.trigger])
    }

    func testShortTapDelaysReleaseForDoubleTapWindow() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        let resolution = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))

        XCTAssertEqual(resolution, .delayed(0.25))
    }

    func testSecondPressWithinWindowEmitsDoubleTapWithoutNewTrigger() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        _ = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))
        let events = stateMachine.handlePress(now: start.addingTimeInterval(0.16))

        XCTAssertEqual(events, [.doubleTap])
    }

    func testExpiredTapWindowReleasesBeforeNextTrigger() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        _ = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))
        let events = stateMachine.handlePress(now: start.addingTimeInterval(0.40))

        XCTAssertEqual(events, [.release, .trigger])
    }

    func testDoubleTapSecondQuickReleaseBecomesPersistent() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        _ = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))
        _ = stateMachine.handlePress(now: start.addingTimeInterval(0.16))
        let resolution = stateMachine.handleRelease(now: start.addingTimeInterval(0.24))

        XCTAssertEqual(resolution, .persistent)
    }

    func testDoubleTapSecondLongHoldStillReleasesNormally() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        _ = stateMachine.handleRelease(now: start.addingTimeInterval(0.08))
        _ = stateMachine.handlePress(now: start.addingTimeInterval(0.16))
        let resolution = stateMachine.handleRelease(now: start.addingTimeInterval(1.30))

        XCTAssertEqual(resolution, .immediate)
    }
}
