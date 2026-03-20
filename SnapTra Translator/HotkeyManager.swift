import AppKit
import Foundation

enum HotkeyGestureEvent: Equatable {
    case trigger
    case release
    case doubleTap
}

enum HotkeyReleaseResolution: Equatable {
    case none
    case immediate
    case delayed(TimeInterval)
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
            // 如果快速释放，返回 .none 保持面板一直显示
            if pressDuration > doubleTapHoldThreshold {
                return .immediate  // 触发 onRelease，支持松开关闭
            } else {
                return .none  // 不触发 onRelease，面板一直显示
            }
        }

        if pressDuration <= tapMaxDuration {
            lastEligibleTapReleaseAt = now
            return .delayed(doubleTapInterval)
        }

        lastEligibleTapReleaseAt = nil
        return .immediate
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

@MainActor
final class HotkeyManager {
    var onTrigger: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activeSingleKey: SingleKey?
    private var pendingRelease: DispatchWorkItem?
    private let releaseConfirmationDelay: TimeInterval = 0.15
    private var gestureStateMachine = HotkeyGestureStateMachine()

    func start(singleKey: SingleKey) {
        stop()
        activeSingleKey = singleKey
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func stop() {
        pendingRelease?.cancel()
        pendingRelease = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        gestureStateMachine.reset()
        activeSingleKey = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let key = activeSingleKey else {
            return
        }
        let keyCode = Int64(event.keyCode)
        let expectedKeyCode = Int64(SingleKeyMapping.keyCode(for: key))

        let targetFlag = SingleKeyMapping.modifierFlag(for: key)
        let eventFlags = event.modifierFlags
        let isTargetFlagPresent = eventFlags.contains(targetFlag)
        let now = Date()

        if isTargetFlagPresent {
            pendingRelease?.cancel()
            pendingRelease = nil
        }

        if isTargetFlagPresent && !gestureStateMachine.isSingleKeyDown {
            guard keyCode == expectedKeyCode else {
                return
            }
            let relevantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
            let otherFlags = eventFlags.intersection(relevantFlags).subtracting(targetFlag)
            guard otherFlags.isEmpty else {
                return
            }
            let events = gestureStateMachine.handlePress(now: now)
            emit(events)
        } else if !isTargetFlagPresent && gestureStateMachine.isSingleKeyDown {
            pendingRelease?.cancel()
            pendingRelease = nil

            let resolution = gestureStateMachine.handleRelease(now: now)
            handleReleaseResolution(resolution, targetFlag: targetFlag)
        }
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
        _ resolution: HotkeyReleaseResolution,
        targetFlag: NSEvent.ModifierFlags
    ) {
        switch resolution {
        case .none:
            return
        case .immediate:
            scheduleReleaseCallback(after: releaseConfirmationDelay, targetFlag: targetFlag)
        case .delayed(let interval):
            scheduleReleaseCallback(after: interval, targetFlag: targetFlag, consumesTapWindow: true)
        }
    }

    private func scheduleReleaseCallback(
        after delay: TimeInterval,
        targetFlag: NSEvent.ModifierFlags,
        consumesTapWindow: Bool = false
    ) {
        let delayedRelease = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !NSEvent.modifierFlags.contains(targetFlag) else { return }
            guard !self.gestureStateMachine.isSingleKeyDown else { return }

            if consumesTapWindow, !self.gestureStateMachine.finalizePendingTapRelease() {
                return
            }

            self.onRelease?()
        }

        pendingRelease?.cancel()
        pendingRelease = delayedRelease
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: delayedRelease)
    }
}

extension HotkeyManager: HotkeyControlling {}
