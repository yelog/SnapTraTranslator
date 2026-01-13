import AppKit
import ApplicationServices
import Combine
import Foundation
import IOKit.hid
import ScreenCaptureKit

struct PermissionStatus: Equatable {
    var screenRecording: Bool
    var inputMonitoring: Bool
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var status: PermissionStatus = PermissionStatus(screenRecording: false, inputMonitoring: false)

    func refreshStatus() {
        Task { await refreshStatusAsync() }
    }

    func refreshStatusAsync() async {
        let screenRecordingAllowed = await screenRecordingStatus()
        let inputMonitoringAllowed = inputMonitoringStatus()
        status = PermissionStatus(screenRecording: screenRecordingAllowed, inputMonitoring: inputMonitoringAllowed)
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func requestAndOpenScreenRecording() {
        requestScreenRecording()
        openScreenRecordingSettings()
        refreshAfterDelay()
    }

    func requestAndOpenInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openInputMonitoringSettings()
        refreshAfterDelay()
    }

    func openScreenRecordingSettings() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    func openInputMonitoringSettings() {
        openPrivacyPane(anchor: "Privacy_ListenEvent")
    }

    private func openPrivacyPane(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) {
            NSWorkspace.shared.open(url)
        }
    }

    private func screenRecordingStatus() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                return false
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 1
            configuration.height = 1
            configuration.queueDepth = 1
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    private func inputMonitoringStatus() -> Bool {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if access == kIOHIDAccessTypeGranted {
            return true
        }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                Unmanaged.passRetained(event)
            },
            userInfo: nil
        )
        guard let tap else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    private func refreshAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshStatus()
        }
    }
}
