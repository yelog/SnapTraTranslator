import AppKit
import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var playPronunciation: Bool {
        didSet { defaults.set(playPronunciation, forKey: AppSettingKey.playPronunciation) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: AppSettingKey.launchAtLogin) }
    }
    @Published var singleKey: SingleKey {
        didSet { defaults.set(singleKey.rawValue, forKey: AppSettingKey.singleKey) }
    }
    @Published var sourceLanguage: String {
        didSet { defaults.set(sourceLanguage, forKey: AppSettingKey.sourceLanguage) }
    }
    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: AppSettingKey.targetLanguage) }
    }
    @Published var debugShowOcrRegion: Bool {
        didSet { defaults.set(debugShowOcrRegion, forKey: AppSettingKey.debugShowOcrRegion) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let playPronunciationValue = defaults.object(forKey: AppSettingKey.playPronunciation) as? Bool
        let launchAtLoginValue = defaults.object(forKey: AppSettingKey.launchAtLogin) as? Bool
        let loginStatus = LoginItemManager.isEnabled()
        let singleKeyValue = defaults.string(forKey: AppSettingKey.singleKey)
        let debugShowOcrRegionValue = defaults.object(forKey: AppSettingKey.debugShowOcrRegion) as? Bool

        playPronunciation = playPronunciationValue ?? true
        launchAtLogin = launchAtLoginValue ?? loginStatus
        singleKey = SingleKey(rawValue: singleKeyValue ?? "rightOption") ?? .rightOption
        sourceLanguage = defaults.string(forKey: AppSettingKey.sourceLanguage) ?? "en"
        targetLanguage = defaults.string(forKey: AppSettingKey.targetLanguage) ?? "zh-Hans"
        debugShowOcrRegion = debugShowOcrRegionValue ?? false
    }

    var hotkeyDisplayText: String {
        singleKey.title
    }
}
