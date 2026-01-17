import AppKit
import ApplicationServices
import Combine
import Foundation
import ScreenCaptureKit

struct PermissionStatus: Equatable {
    var screenRecording: Bool
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var status: PermissionStatus = PermissionStatus(screenRecording: false)

    func refreshStatus() {
        Task { await refreshStatusAsync() }
    }

    func refreshStatusAsync() async {
        let screenRecordingAllowed = await screenRecordingStatus()
        status = PermissionStatus(screenRecording: screenRecordingAllowed)
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func requestAndOpenScreenRecording() {
        requestScreenRecording()
        openScreenRecordingSettings()
        refreshAfterDelay()
    }

    func openScreenRecordingSettings() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
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

    private func refreshAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshStatus()
        }
    }
}
