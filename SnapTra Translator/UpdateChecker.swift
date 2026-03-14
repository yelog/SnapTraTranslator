import AppKit
import Foundation
import Sparkle

enum DistributionChannel {
    case github
    case appStore

    static var current: DistributionChannel {
        // First check explicit marker in Info.plist
        if let channel = Bundle.main.infoDictionary?["DISTRIBUTION_CHANNEL"] as? String,
           channel == "github" {
            return .github
        }

        // Then check App Store receipt
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            // Check if receipt actually exists on disk
            if FileManager.default.fileExists(atPath: receiptURL.path) {
                return .appStore
            }
        }

        // Default to GitHub for non-App Store builds
        return .github
    }

    static var isGitHubRelease: Bool {
        current == .github
    }
}

@MainActor
final class UpdateChecker: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateChecker()

    private var updaterController: SPUStandardUpdaterController?
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var autoCheckTimer: Timer?

    var isGitHubRelease: Bool {
        DistributionChannel.isGitHubRelease
    }

    private override init() {
        super.init()
    }

    func initialize() {
        guard updaterController == nil else { return }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        if let updater = updaterController?.updater {
            updater.automaticallyChecksForUpdates = SettingsStore.shared.autoCheckUpdates && isGitHubRelease
            updater.updateCheckInterval = checkInterval
        }
    }

    func updateFeedURL() {
        updaterController?.updater.clearFeedURLFromUserDefaults()
    }

    func startAutoCheckIfNeeded() {
        guard isGitHubRelease else { return }
        guard SettingsStore.shared.autoCheckUpdates else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates(silent: true)
        }

        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard SettingsStore.shared.autoCheckUpdates else { return }
                self?.checkForUpdates(silent: true)
            }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        if isGitHubRelease {
            if let controller = updaterController {
                if silent {
                    controller.updater.checkForUpdatesInBackground()
                } else {
                    controller.checkForUpdates(nil)
                }
            } else if !silent {
                showSparkleNotInitializedAlert()
            }
        } else {
            guard !silent else { return }
            openAppStore()
        }
    }

    func checkForUpdatesWithUI() {
        if isGitHubRelease {
            if let controller = updaterController {
                controller.checkForUpdates(nil)
            } else {
                showSparkleNotInitializedAlert()
            }
        } else {
            openAppStore()
        }
    }

    // MARK: - App Store

    private func openAppStore() {
        if let url = URL(string: "https://apps.apple.com/cn/app/snaptra-translator/id6757981764") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        let channel = SettingsStore.shared.updateChannel
        let url: String
        switch channel {
        case .stable:
            url = "https://snaptra.yelog.org/appcast.xml"
        case .beta:
            url = "https://snaptra.yelog.org/appcast-beta.xml"
        }
        print("[UpdateChecker] Using feed URL for channel '\(channel)': \(url)")
        return url
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("[UpdateChecker] Update found: \(item.displayVersionString)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        print("[UpdateChecker] No update found")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("[UpdateChecker] Update aborted with error: \(error.localizedDescription)")

        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case 1001:
                print("[UpdateChecker] Already up to date")
                return
            case 4007:
                print("[UpdateChecker] Update was canceled by user")
                return
            default:
                break
            }
        }

        DispatchQueue.main.async {
            self.showUpdateFailedAlert(error: error)
        }
    }

    // MARK: - Alerts

    private func showSparkleNotInitializedAlert() {
        let alert = NSAlert()
        alert.messageText = L("Update Check Failed")
        alert.informativeText = L("Auto-updater is not available. Please visit GitHub to download the latest version.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Go to GitHub"))
        alert.addButton(withTitle: L("OK"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/yelog/SnapTraTranslator/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showUpdateFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Update Check Failed")
        alert.informativeText = "\(L("Auto-update failed. You can download the latest version from GitHub."))\n\n\(L("Error")): \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Download from GitHub"))
        alert.addButton(withTitle: L("OK"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/yelog/SnapTraTranslator/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
