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
    @Published var translationEngine: TranslationEngineType {
        didSet { defaults.set(translationEngine.rawValue, forKey: AppSettingKey.translationEngine) }
    }
    @Published var engineConfigurations: EngineConfigurations {
        didSet {
            if let data = try? JSONEncoder().encode(engineConfigurations) {
                defaults.set(data, forKey: AppSettingKey.engineConfigurations)
            }
        }
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
        singleKey = SingleKey(rawValue: singleKeyValue ?? "rightOption") ?? .rightOption
        sourceLanguage = defaults.string(forKey: AppSettingKey.sourceLanguage) ?? "en"
        targetLanguage = defaults.string(forKey: AppSettingKey.targetLanguage) ?? "zh-Hans"
        debugShowOcrRegion = debugShowOcrRegionValue ?? false
        continuousTranslation = continuousTranslationValue ?? true

        // Translation engine
        let engineRawValue = defaults.string(forKey: AppSettingKey.translationEngine) ?? "apple"
        translationEngine = TranslationEngineType(rawValue: engineRawValue) ?? .apple

        // Engine configurations
        if let data = defaults.data(forKey: AppSettingKey.engineConfigurations),
           let configs = try? JSONDecoder().decode(EngineConfigurations.self, from: data) {
            engineConfigurations = configs
        } else {
            engineConfigurations = EngineConfigurations()
        }
    }

    var hotkeyDisplayText: String {
        singleKey.title
    }
}
