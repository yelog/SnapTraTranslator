import AppKit
import Carbon
import Foundation
import OSLog

enum HotkeyGestureEvent: Equatable {
    case trigger
    case release
    case doubleTap
}

enum HotkeyReleaseKind: Equatable {
    case tap
    case hold
}

enum HotkeyReleaseResolution: Equatable {
    case none
    case immediate(HotkeyReleaseKind)
    case delayed(TimeInterval, HotkeyReleaseKind)
    case persistent
}

struct HotkeyGestureStateMachine {
    private(set) var isSingleKeyDown = false

    private var pressBeganAt: Date?
    private var lastEligibleTapReleaseAt: Date?
    private var currentPressWasDoubleTap = false

    let doubleTapInterval: TimeInterval
    let tapMaxDuration: TimeInterval

    // 双击后长按阈值，超过此时间视为"按住显示模式"
    let doubleTapHoldThreshold: TimeInterval

    init(
        doubleTapInterval: TimeInterval = 0.25,
        tapMaxDuration: TimeInterval = 0.18,
        doubleTapHoldThreshold: TimeInterval = 1.0
    ) {
        self.doubleTapInterval = doubleTapInterval
        self.tapMaxDuration = tapMaxDuration
        self.doubleTapHoldThreshold = doubleTapHoldThreshold
    }

    mutating func handlePress(now: Date) -> [HotkeyGestureEvent] {
        var events: [HotkeyGestureEvent] = []

        if let lastEligibleTapReleaseAt,
           now.timeIntervalSince(lastEligibleTapReleaseAt) > doubleTapInterval {
            self.lastEligibleTapReleaseAt = nil
            events.append(.release)
        }

        guard !isSingleKeyDown else {
            return events
        }

        isSingleKeyDown = true
        pressBeganAt = now

        if let lastEligibleTapReleaseAt,
           now.timeIntervalSince(lastEligibleTapReleaseAt) <= doubleTapInterval {
            currentPressWasDoubleTap = true
            self.lastEligibleTapReleaseAt = nil
            events.append(.doubleTap)
        } else {
            currentPressWasDoubleTap = false
            events.append(.trigger)
        }

        return events
    }

    mutating func handleRelease(now: Date) -> HotkeyReleaseResolution {
        guard isSingleKeyDown else {
            return .none
        }

        isSingleKeyDown = false
        let pressDuration = pressBeganAt.map { now.timeIntervalSince($0) } ?? 0
        pressBeganAt = nil

        if currentPressWasDoubleTap {
            currentPressWasDoubleTap = false
            lastEligibleTapReleaseAt = nil

            // 检测双击后的按住时间
            // 如果按住超过阈值，返回 .immediate 让用户可以松开关闭面板
            // 如果快速释放，返回 .persistent 保持面板一直显示并切换为常驻态
            if pressDuration > doubleTapHoldThreshold {
                return .immediate(.hold)  // 触发 onRelease，支持松开关闭
            } else {
                return .persistent
            }
        }

        if pressDuration <= tapMaxDuration {
            lastEligibleTapReleaseAt = now
            return .delayed(doubleTapInterval, .tap)
        }

        lastEligibleTapReleaseAt = nil
        return .immediate(.hold)
    }

    mutating func finalizePendingTapRelease() -> Bool {
        guard lastEligibleTapReleaseAt != nil else {
            return false
        }

        lastEligibleTapReleaseAt = nil
        return true
    }

    mutating func reset() {
        isSingleKeyDown = false
        pressBeganAt = nil
        lastEligibleTapReleaseAt = nil
        currentPressWasDoubleTap = false
    }
}

final class HotkeyManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SnapTraTranslator",
        category: "Hotkey"
    )

    var onTrigger: (() -> Void)?
    var onRelease: (() -> Void)?
    var onTapRelease: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onPersistentRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activeSingleKey: SingleKey?
    private var isTargetKeyDown = false
    private var pendingRelease: DispatchWorkItem?
    private let releaseConfirmationDelay: TimeInterval = 0.15
    private var gestureStateMachine = HotkeyGestureStateMachine()

    func start(singleKey: SingleKey) {
        stop()
        activeSingleKey = singleKey
        Self.logger.debug(
            "Hotkey monitor started key=\(singleKey.rawValue, privacy: .public) keyCode=\(SingleKeyMapping.keyCode(for: singleKey), privacy: .public)"
        )
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleFlagsChanged(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    func resetState() {
        pendingRelease?.cancel()
        pendingRelease = nil
        gestureStateMachine.reset()
        isTargetKeyDown = false
    }

    func stop() {
        resetState()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        activeSingleKey = nil
    }

    func handleFlagsChanged(_ event: NSEvent, now: Date = Date()) {
        guard let key = activeSingleKey else {
            return
        }
        let keyCode = Int64(event.keyCode)
        let expectedKeyCode = Int64(SingleKeyMapping.keyCode(for: key))

        // ModifierFlags.option is an aggregate left/right state. Use the
        // physical key code for the configured key so releasing Right Option
        // is not lost while Left Option remains pressed (and vice versa).
        guard keyCode == expectedKeyCode else {
            return
        }

        let eventFlags = event.modifierFlags

        Self.logger.debug(
            "flagsChanged keyCode=\(event.keyCode, privacy: .public) flags=\(eventFlags.rawValue, privacy: .public) stateDown=\(self.isTargetKeyDown, privacy: .public)"
        )

        // Track physical state even when a combination is ineligible to
        // trigger a gesture. Device-specific flags distinguish the two sides
        // and let a release be recognized without a preceding press event.
        let isPressed = Self.isPressed(key, in: eventFlags)
        guard isPressed != isTargetKeyDown else { return }
        isTargetKeyDown = isPressed

        if isPressed {
            let relevantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
            let targetFlag = SingleKeyMapping.modifierFlag(for: key)
            let otherFlags = eventFlags.intersection(relevantFlags).subtracting(targetFlag)
            guard otherFlags.isEmpty else {
                return
            }

            pendingRelease?.cancel()
            pendingRelease = nil
            let events = gestureStateMachine.handlePress(now: now)
            emit(events)
        } else {
            guard gestureStateMachine.isSingleKeyDown else { return }
            pendingRelease?.cancel()
            pendingRelease = nil

            let resolution = gestureStateMachine.handleRelease(now: now)
            handleReleaseResolution(resolution)
        }
    }

    private static func isPressed(_ key: SingleKey, in flags: NSEvent.ModifierFlags) -> Bool {
        let mask: Int32
        switch key {
        case .leftShift: mask = NX_DEVICELSHIFTKEYMASK
        case .rightShift: mask = NX_DEVICERSHIFTKEYMASK
        case .leftControl: mask = NX_DEVICELCTLKEYMASK
        case .rightControl: mask = NX_DEVICERCTLKEYMASK
        case .leftOption: mask = NX_DEVICELALTKEYMASK
        case .rightOption: mask = NX_DEVICERALTKEYMASK
        case .leftCommand: mask = NX_DEVICELCMDKEYMASK
        case .rightCommand: mask = NX_DEVICERCMDKEYMASK
        case .fn: return flags.contains(.function)
        }
        return flags.rawValue & UInt(mask) != 0
    }

    private func emit(_ events: [HotkeyGestureEvent]) {
        for event in events {
            switch event {
            case .trigger:
                onTrigger?()
            case .release:
                onRelease?()
            case .doubleTap:
                onDoubleTap?()
            }
        }
    }

    private func handleReleaseResolution(
        _ resolution: HotkeyReleaseResolution
    ) {
        switch resolution {
        case .none:
            return
        case .immediate(let kind):
            scheduleReleaseCallback(after: releaseConfirmationDelay, releaseKind: kind)
        case .delayed(let interval, let kind):
            scheduleReleaseCallback(after: interval, consumesTapWindow: true, releaseKind: kind)
        case .persistent:
            onPersistentRelease?()
        }
    }

    private func scheduleReleaseCallback(
        after delay: TimeInterval,
        consumesTapWindow: Bool = false,
        releaseKind: HotkeyReleaseKind
    ) {
        let delayedRelease = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // An ineligible modifier combination must not suppress the
            // pending release of the previous standalone gesture.
            guard !self.gestureStateMachine.isSingleKeyDown else { return }

            if consumesTapWindow, !self.gestureStateMachine.finalizePendingTapRelease() {
                return
            }

            switch releaseKind {
            case .tap:
                if let onTapRelease = self.onTapRelease {
                    onTapRelease()
                } else {
                    self.onRelease?()
                }
            case .hold:
                self.onRelease?()
            }
        }

        pendingRelease?.cancel()
        pendingRelease = delayedRelease
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: delayedRelease)
    }
}
