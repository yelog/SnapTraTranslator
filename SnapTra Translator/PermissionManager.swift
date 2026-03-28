import AppKit
import ApplicationServices
import Combine
import Foundation
import ScreenCaptureKit

struct PermissionStatus: Equatable {
    var screenRecording: Bool
    var accessibility: Bool
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var status: PermissionStatus = PermissionStatus(
        screenRecording: false,
        accessibility: false
    )

    func refreshStatus() {
        Task { await refreshStatusAsync() }
    }

    func refreshStatusAsync() async {
        let screenRecordingAllowed = await screenRecordingStatus()
        let accessibilityAllowed = accessibilityStatus()
        status = PermissionStatus(
            screenRecording: screenRecordingAllowed,
            accessibility: accessibilityAllowed
        )
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func requestAndOpenScreenRecording() {
        requestScreenRecording()
        openScreenRecordingSettings()
        refreshAfterDelay()
    }

    func requestAccessibility() {
        activateAppForPermissionPrompt()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestAndOpenAccessibility() {
        guard !accessibilityStatus() else {
            openAccessibilitySettings()
            refreshAfterDelay()
            return
        }

        requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.accessibilityStatus() else { return }
            self.openAccessibilitySettings()
        }
        refreshAfterDelay()
        refreshAfterDelay(seconds: 1.5)
        refreshAfterDelay(seconds: 3.0)
    }

    func openScreenRecordingSettings() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
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

    private func accessibilityStatus() -> Bool {
        AXIsProcessTrusted()
    }

    private func activateAppForPermissionPrompt() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshAfterDelay(seconds: TimeInterval = 0.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.refreshStatus()
        }
    }
}
