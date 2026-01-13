import AppKit
import Carbon
import Foundation

final class HotkeyManager {
    var onTrigger: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSingleKeyDown = false
    private var activeSingleKey: SingleKey?
    private var pendingRelease: DispatchWorkItem?
    private let releaseConfirmationDelay: TimeInterval = 0.15

    func start(singleKey: SingleKey) {
        stop()
        startSingleKeyTap(key: singleKey)
    }

    func stop() {
        pendingRelease?.cancel()
        pendingRelease = nil
        stopSingleKeyTap()
    }

    private func startSingleKeyTap(key: SingleKey) {
        activeSingleKey = key
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    manager.enableEventTap()
                    return Unmanaged.passRetained(event)
                }
                manager.handleFlagsChanged(event: event, type: type, proxy: proxy)
                return Unmanaged.passRetained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func stopSingleKeyTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        isSingleKeyDown = false
        activeSingleKey = nil
    }

    private func enableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func handleFlagsChanged(event: CGEvent, type: CGEventType, proxy: CGEventTapProxy) {
        guard type == .flagsChanged else {
            return
        }
        guard let key = activeSingleKey else {
            return
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let expectedKeyCode = Int64(SingleKeyMapping.keyCode(for: key))
        let isOptionKey = key == .leftOption || key == .rightOption
        
        let targetFlag = SingleKeyMapping.modifierFlag(for: key)
        let eventFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let isTargetFlagPresent = eventFlags.contains(targetFlag)
        
        if isTargetFlagPresent {
            pendingRelease?.cancel()
            pendingRelease = nil
        }
        if isTargetFlagPresent && !isSingleKeyDown {
            if !isOptionKey {
                guard keyCode == expectedKeyCode else {
                    return
                }
            }
            let relevantFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
            let otherFlags = eventFlags.intersection(relevantFlags).subtracting(targetFlag)
            guard otherFlags.isEmpty else {
                return
            }
            isSingleKeyDown = true
            onTrigger?()
        } else if !isTargetFlagPresent && isSingleKeyDown {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !NSEvent.modifierFlags.contains(targetFlag) else { return }
                guard self.isSingleKeyDown else { return }
                self.isSingleKeyDown = false
                self.onRelease?()
            }
            pendingRelease?.cancel()
            pendingRelease = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + releaseConfirmationDelay, execute: workItem)
        }
    }
}
