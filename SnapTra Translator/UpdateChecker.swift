import AppKit
import Combine
import Foundation
#if DIRECT_DISTRIBUTION
import Sparkle
#endif

enum DistributionChannel {
    case github
    case appStore

    static var current: DistributionChannel {
        if let channel = Bundle.main.infoDictionary?["DISTRIBUTION_CHANNEL"] as? String,
           channel == "github" {
            return .github
        }
        return .appStore
    }

    var supportsSelectedTextTranslation: Bool {
        switch self {
        case .github:
            return true
        case .appStore:
            return false
        }
    }

    static var supportsSelectedTextTranslation: Bool {
        current.supportsSelectedTextTranslation
    }

    static var isGitHubRelease: Bool {
        current == .github
    }
}

@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()

    enum CheckTrigger {
        case none
        case automaticSilent
        case userInitiated
    }

    let checkInterval: TimeInterval = 24 * 60 * 60
    let checkTimeout: TimeInterval = 60
    let silentRetryDelay: TimeInterval = 5 * 60

    @Published var isCheckingForUpdates = false

    var isGitHubRelease: Bool {
        #if DEBUG
        let debugEnabled = UserDefaults.standard.bool(forKey: AppSettingKey.debugShowChannelSelector)
        if debugEnabled {
            return true
        }
        #endif
        return DistributionChannel.isGitHubRelease
    }

    private override init() {
        super.init()
    }

    fileprivate func openAppStore() {
        if let url = URL(string: "https://apps.apple.com/cn/app/snaptra-translator/id6757981764") {
            NSWorkspace.shared.open(url)
        }
    }

    fileprivate func openGitHubReleases() {
        let channelValue = UserDefaults.standard.string(forKey: AppSettingKey.updateChannel) ?? "stable"
        let channel = UpdateChannel(rawValue: channelValue) ?? .stable

        let urlString: String
        switch channel {
        case .stable:
            urlString = "https://github.com/yelog/SnapTraTranslator/releases/latest"
        case .beta:
            urlString = "https://github.com/yelog/SnapTraTranslator/releases"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    fileprivate func showSparkleNotInitializedAlert() {
        let alert = NSAlert()
        alert.messageText = L("Update Check Failed")
        alert.informativeText = L("Auto-updater is not available. Please visit GitHub to download the latest version.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("Go to GitHub"))
        alert.addButton(withTitle: L("OK"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openGitHubReleases()
        }
    }

    fileprivate func showUpdateFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Update Check Failed")
        alert.informativeText = "\(L("Auto-update failed. You can download the latest version from GitHub."))\n\n\(L("Error")): \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Download from GitHub"))
        alert.addButton(withTitle: L("OK"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openGitHubReleases()
        }
    }
}

#if DIRECT_DISTRIBUTION
@MainActor
extension UpdateChecker: SPUUpdaterDelegate {
    private struct SparkleState {
        static var updaterController: SPUStandardUpdaterController?
        static var autoCheckTimer: Timer?
        static var checkTimeoutTimer: Timer?
        static var pendingSilentRetryWorkItem: DispatchWorkItem?
        static var activeCheckTrigger: CheckTrigger = .none
    }

    func initialize() {
        guard SparkleState.updaterController == nil else { return }

        SparkleState.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        if let updater = SparkleState.updaterController?.updater {
            updater.automaticallyChecksForUpdates = SettingsStore.shared.autoCheckUpdates && isGitHubRelease
            updater.updateCheckInterval = checkInterval
        }
    }

    func updateFeedURL() {
        guard let updater = SparkleState.updaterController?.updater else { return }

        updater.clearFeedURLFromUserDefaults()

        let defaults = UserDefaults.standard
        let sparkleKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("SU") }
        for key in sparkleKeys {
            defaults.removeObject(forKey: key)
        }

        updater.resetUpdateCycle()

        print("[UpdateChecker] Feed URL updated, Sparkle cache cleared for channel: \(SettingsStore.shared.updateChannel)")
    }

    func startAutoCheckIfNeeded() {
        guard isGitHubRelease else { return }
        guard SettingsStore.shared.autoCheckUpdates else { return }

        scheduleSilentAutoCheck(after: 5)

        SparkleState.autoCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard SettingsStore.shared.autoCheckUpdates else { return }
                self?.checkForUpdates(silent: true)
            }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        guard SparkleState.activeCheckTrigger == .none else {
            print("[UpdateChecker] Update check already in progress, skipping")
            return
        }

        if isGitHubRelease {
            if let controller = SparkleState.updaterController {
                SparkleState.activeCheckTrigger = silent ? .automaticSilent : .userInitiated
                if silent {
                    controller.updater.checkForUpdatesInBackground()
                } else {
                    startUpdateCheck()
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
        guard SparkleState.activeCheckTrigger == .none else {
            print("[UpdateChecker] Update check already in progress, skipping")
            return
        }

        if isGitHubRelease {
            if let controller = SparkleState.updaterController {
                SparkleState.activeCheckTrigger = .userInitiated
                startUpdateCheck()
                controller.checkForUpdates(nil)
            } else {
                showSparkleNotInitializedAlert()
            }
        } else {
            openAppStore()
        }
    }

    private func startUpdateCheck() {
        isCheckingForUpdates = true

        SparkleState.checkTimeoutTimer?.invalidate()
        SparkleState.checkTimeoutTimer = Timer.scheduledTimer(withTimeInterval: checkTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetUpdateCheckState()
                print("[UpdateChecker] Update check timed out after \(self?.checkTimeout ?? 0)s")
            }
        }
    }

    private func resetUpdateCheckState() {
        isCheckingForUpdates = false
        SparkleState.checkTimeoutTimer?.invalidate()
        SparkleState.checkTimeoutTimer = nil
        SparkleState.activeCheckTrigger = .none
    }

    private func scheduleSilentAutoCheck(after delay: TimeInterval) {
        SparkleState.pendingSilentRetryWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard SettingsStore.shared.autoCheckUpdates, self.isGitHubRelease else { return }
            self.checkForUpdates(silent: true)
        }

        SparkleState.pendingSilentRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        let channelValue = UserDefaults.standard.string(forKey: AppSettingKey.updateChannel) ?? "stable"
        let channel = UpdateChannel(rawValue: channelValue) ?? .stable

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
        resetUpdateCheckState()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        print("[UpdateChecker] No update found")
        resetUpdateCheckState()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let trigger = SparkleState.activeCheckTrigger
        print("[UpdateChecker] Update aborted with error: \(error.localizedDescription)")
        resetUpdateCheckState()

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

        guard trigger == .userInitiated else {
            print("[UpdateChecker] Silent update check failed, retrying in \(Int(silentRetryDelay)) seconds")
            scheduleSilentAutoCheck(after: silentRetryDelay)
            return
        }

        DispatchQueue.main.async {
            self.showUpdateFailedAlert(error: error)
        }
    }
}
#else
@MainActor
extension UpdateChecker {
    func initialize() {}

    func updateFeedURL() {}

    func startAutoCheckIfNeeded() {}

    func checkForUpdates(silent: Bool = false) {
        guard !silent else { return }
        openAppStore()
    }

    func checkForUpdatesWithUI() {
        guard !isCheckingForUpdates else {
            print("[UpdateChecker] Update check already in progress, skipping")
            return
        }
        openAppStore()
    }
}
#endif
