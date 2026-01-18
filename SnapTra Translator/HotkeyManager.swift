import AppKit
import Foundation

final class HotkeyManager {
    var onTrigger: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isSingleKeyDown = false
    private var activeSingleKey: SingleKey?
    private var pendingRelease: DispatchWorkItem?
    private let releaseConfirmationDelay: TimeInterval = 0.15

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
        isSingleKeyDown = false
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

        if isTargetFlagPresent {
            pendingRelease?.cancel()
            pendingRelease = nil
        }
        if isTargetFlagPresent && !isSingleKeyDown {
            guard keyCode == expectedKeyCode else {
                return
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
