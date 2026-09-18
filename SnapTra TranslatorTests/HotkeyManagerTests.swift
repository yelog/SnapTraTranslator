import AppKit
import Carbon
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

        XCTAssertEqual(resolution, .delayed(0.25, .tap))
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

        XCTAssertEqual(resolution, .immediate(.hold))
    }

    func testLongPressReleaseEmitsImmediateRelease() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        let resolution = stateMachine.handleRelease(now: start.addingTimeInterval(0.30))

        XCTAssertEqual(resolution, .immediate(.hold))
    }

    func testResetAllowsFreshPressAfterLostRelease() {
        var stateMachine = HotkeyGestureStateMachine()
        let start = Date()

        _ = stateMachine.handlePress(now: start)
        stateMachine.reset()
        let events = stateMachine.handlePress(now: start.addingTimeInterval(2.0))

        XCTAssertEqual(events, [.trigger])
    }

    @MainActor
    func testRejectedModifierCombinationDoesNotTriggerOnRelease() throws {
        let manager = HotkeyManager()
        manager.start(singleKey: .rightOption)
        defer { manager.stop() }
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }
        let start = Date()
        let command = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCMDKEYMASK)).union(.command)
        let option = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK)).union(.option)

        manager.handleFlagsChanged(try modifierEvent(keyCode: 55, flags: command), now: start)
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: command.union(option)), now: start)
        manager.handleFlagsChanged(try modifierEvent(keyCode: 55, flags: option), now: start)
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: []), now: start)
        XCTAssertEqual(triggerCount, 0)

        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: option), now: start.addingTimeInterval(1))
        XCTAssertEqual(triggerCount, 1)
    }

    @MainActor
    func testRightOptionReleaseIsRecognizedWhileLeftOptionRemainsDown() throws {
        let manager = HotkeyManager()
        manager.start(singleKey: .rightOption)
        defer { manager.stop() }
        var doubleTapCount = 0
        var persistentReleaseCount = 0
        manager.onDoubleTap = { doubleTapCount += 1 }
        manager.onPersistentRelease = { persistentReleaseCount += 1 }
        let start = Date()
        let left = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELALTKEYMASK)).union(.option)
        let both = left.union(NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK)))

        manager.handleFlagsChanged(try modifierEvent(keyCode: 58, flags: left), now: start)
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: both), now: start)
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: left), now: start.addingTimeInterval(0.08))
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: both), now: start.addingTimeInterval(0.16))
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: left), now: start.addingTimeInterval(0.24))

        XCTAssertEqual(doubleTapCount, 1)
        XCTAssertEqual(persistentReleaseCount, 1)
    }

    @MainActor
    func testReleaseAfterResetDoesNotStartLookup() throws {
        let manager = HotkeyManager()
        manager.start(singleKey: .rightOption)
        defer { manager.stop() }
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }
        let option = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK)).union(.option)

        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: option))
        manager.resetState()
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: []))
        XCTAssertEqual(triggerCount, 1)

        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: option))
        XCTAssertEqual(triggerCount, 2)
    }

    @MainActor
    func testDuplicatePressDoesNotBecomeReleaseOrDoubleTap() throws {
        let manager = HotkeyManager()
        manager.start(singleKey: .rightOption)
        defer { manager.stop() }
        var triggerCount = 0
        var doubleTapCount = 0
        manager.onTrigger = { triggerCount += 1 }
        manager.onDoubleTap = { doubleTapCount += 1 }
        let option = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK)).union(.option)
        let event = try modifierEvent(keyCode: 61, flags: option)

        for _ in 0..<3 {
            manager.handleFlagsChanged(event)
        }

        XCTAssertEqual(triggerCount, 1)
        XCTAssertEqual(doubleTapCount, 0)
    }

    @MainActor
    func testRejectedCombinationDoesNotSuppressPendingTapRelease() async throws {
        let manager = HotkeyManager()
        manager.start(singleKey: .rightOption)
        defer { manager.stop() }
        let released = expectation(description: "Standalone tap is released during a modifier combination")
        manager.onTapRelease = { released.fulfill() }
        let start = Date()
        let option = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK)).union(.option)
        let command = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCMDKEYMASK)).union(.command)

        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: option), now: start)
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: []), now: start.addingTimeInterval(0.08))
        manager.handleFlagsChanged(try modifierEvent(keyCode: 55, flags: command), now: start.addingTimeInterval(0.10))
        manager.handleFlagsChanged(try modifierEvent(keyCode: 61, flags: command.union(option)), now: start.addingTimeInterval(0.12))

        await fulfillment(of: [released], timeout: 2)
    }

    private func modifierEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
