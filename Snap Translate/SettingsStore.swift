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
    @Published var continuousTranslation: Bool {
        didSet { defaults.set(continuousTranslation, forKey: AppSettingKey.continuousTranslation) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let playPronunciationValue = defaults.object(forKey: AppSettingKey.playPronunciation) as? Bool
        let launchAtLoginValue = defaults.object(forKey: AppSettingKey.launchAtLogin) as? Bool
        let loginStatus = LoginItemManager.isEnabled()
        let singleKeyValue = defaults.string(forKey: AppSettingKey.singleKey)
        let debugShowOcrRegionValue = defaults.object(forKey: AppSettingKey.debugShowOcrRegion) as? Bool
        let continuousTranslationValue = defaults.object(forKey: AppSettingKey.continuousTranslation) as? Bool

        playPronunciation = playPronunciationValue ?? true
        launchAtLogin = launchAtLoginValue ?? loginStatus
        singleKey = SingleKey(rawValue: singleKeyValue ?? "leftControl") ?? .leftControl
        sourceLanguage = defaults.string(forKey: AppSettingKey.sourceLanguage) ?? "en"
        let defaultTarget = Self.defaultTargetLanguage()
        targetLanguage = defaults.string(forKey: AppSettingKey.targetLanguage) ?? defaultTarget
        debugShowOcrRegion = debugShowOcrRegionValue ?? false
        continuousTranslation = continuousTranslationValue ?? true
    }

    var hotkeyDisplayText: String {
        singleKey.title
    }

    private static func defaultTargetLanguage() -> String {
        let supportedLanguages = [
            "zh-Hans",
            "zh-Hant",
            "en",
            "ja",
            "ko",
            "fr",
            "de",
            "es",
            "it",
            "pt",
            "ru",
            "ar",
            "th",
            "vi",
        ]
        
        let preferredLanguages = Locale.preferredLanguages
        for preferred in preferredLanguages {
            let identifier = Locale(identifier: preferred).language.minimalIdentifier
            
            if supportedLanguages.contains(identifier) {
                if identifier != "en" {
                    return identifier
                }
            }
            
            if identifier.hasPrefix("zh") {
                let script = Locale(identifier: preferred).language.script?.identifier
                if script == "Hant" {
                    return "zh-Hant"
                } else {
                    return "zh-Hans"
                }
            }
        }

        return "zh-Hans"
    }
}
