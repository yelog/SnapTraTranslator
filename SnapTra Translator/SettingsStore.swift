import AppKit
import Combine
import Foundation

@MainActor
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
    @Published var dictionarySources: [DictionarySource] {
        didSet {
            saveDictionarySources()
        }
    }
    @Published var ttsProvider: TTSProvider {
        didSet { defaults.set(ttsProvider.rawValue, forKey: AppSettingKey.ttsProvider) }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: AppSettingKey.appLanguage)
            LocalizationManager.shared.setLanguage(appLanguage)
        }
    }
    @Published var englishAccent: EnglishAccent {
        didSet { defaults.set(englishAccent.rawValue, forKey: AppSettingKey.englishAccent) }
    }

    private let defaults: UserDefaults
    private static let dictionarySourcesKey = "dictionarySources"

    init(defaults: UserDefaults = .standard, loginItemStatus: Bool? = nil) {
        self.defaults = defaults
        let playPronunciationValue = defaults.object(forKey: AppSettingKey.playPronunciation) as? Bool
        let launchAtLoginValue = defaults.object(forKey: AppSettingKey.launchAtLogin) as? Bool
        let loginStatus = loginItemStatus ?? LoginItemManager.isEnabled()
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

        // Load or migrate dictionary sources
        dictionarySources = Self.loadOrMigrateDictionarySources(defaults: defaults)
        
        // Load TTS provider (migrate removed "edge" → "bing")
        var ttsProviderValue = defaults.string(forKey: AppSettingKey.ttsProvider)
        if ttsProviderValue == "edge" { ttsProviderValue = "bing" }
        ttsProvider = TTSProvider(rawValue: ttsProviderValue ?? "apple") ?? .apple
        
        // Load app language
        let appLanguageValue = defaults.string(forKey: AppSettingKey.appLanguage)
        appLanguage = AppLanguage(rawValue: appLanguageValue ?? "system") ?? .system
        
        // Load English accent preference
        let englishAccentValue = defaults.string(forKey: AppSettingKey.englishAccent)
        englishAccent = EnglishAccent(rawValue: englishAccentValue ?? "en-US") ?? .american
    }

    private static func loadOrMigrateDictionarySources(defaults: UserDefaults) -> [DictionarySource] {
        // Try to load existing sources
        if let data = defaults.data(forKey: dictionarySourcesKey),
           let sources = try? JSONDecoder().decode([DictionarySource].self, from: data) {
            let migrated = migrateDictionarySources(sources)
            persistDictionarySources(migrated, defaults: defaults)
            return migrated
        }

        let sources = defaultDictionarySources()
        persistDictionarySources(sources, defaults: defaults)
        return sources
    }

    private func saveDictionarySources() {
        Self.persistDictionarySources(dictionarySources, defaults: defaults)
    }

    var hotkeyDisplayText: String {
        singleKey.title
    }

    private static func defaultTargetLanguage() -> String {
        let supportedLanguages: Set<String> = [
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
        guard let firstPreferred = preferredLanguages.first else {
            return "zh-Hans"
        }
        
        let locale = Locale(identifier: firstPreferred)
        let languageCode = locale.language.languageCode?.identifier ?? ""
        
        if languageCode == "zh" {
            let script = locale.language.script?.identifier
            return script == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        
        if supportedLanguages.contains(languageCode) {
            return languageCode
        }

        return "zh-Hans"
    }

    static func defaultDictionarySources(ecdictInstalled: Bool) -> [DictionarySource] {
        [
            makeDictionarySource(type: .ecdict, isEnabled: ecdictInstalled),
            makeDictionarySource(type: .system, isEnabled: true),
            makeDictionarySource(type: .freeDict, isEnabled: true),
        ]
    }

    static func migrateDictionarySources(_ sources: [DictionarySource]) -> [DictionarySource] {
        let hiddenTypes: Set<DictionarySource.SourceType> = [.google, .bing, .youdao, .deepl]

        let filtered = sources.filter { !hiddenTypes.contains($0.type) }

        // Add freeDict if not present
        var result = filtered
        if !result.contains(where: { $0.type == .freeDict }) {
            result.append(makeDictionarySource(type: .freeDict, isEnabled: true))
        }

        let migrated: [DictionarySource] = result.map {
            DictionarySource(
                id: $0.id,
                name: $0.type.displayName,
                type: $0.type,
                isEnabled: $0.isEnabled
            )
        }

        return migrated
    }

    private static func defaultDictionarySources() -> [DictionarySource] {
        defaultDictionarySources(ecdictInstalled: isECDICTInstalled)
    }

    private static func makeDictionarySource(
        type: DictionarySource.SourceType,
        isEnabled: Bool
    ) -> DictionarySource {
        DictionarySource(
            id: UUID(),
            name: type.displayName,
            type: type,
            isEnabled: isEnabled
        )
    }

    private static func persistDictionarySources(
        _ sources: [DictionarySource],
        defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: dictionarySourcesKey)
        }
    }

    private static var isECDICTInstalled: Bool {
        FileManager.default.fileExists(atPath: OfflineDictionaryService.databaseURL.path)
    }
}
