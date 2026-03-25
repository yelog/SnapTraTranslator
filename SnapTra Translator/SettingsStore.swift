import AppKit
import Combine
import Foundation

// MARK: - Sentence Translation Source

struct SentenceTranslationSource: Identifiable, Codable, Equatable {
    let id: UUID
    let type: SourceType
    var isEnabled: Bool

    enum SourceType: String, Codable {
        case native     // macOS Translation
        case google
        case bing
        case youdao
    }

    var displayName: String {
        type.displayName
    }

    var subtitle: String {
        type.subtitle
    }

    var isNative: Bool {
        type == .native
    }
}

extension SentenceTranslationSource.SourceType {
    var displayName: String {
        switch self {
        case .native:
            return String(localized: "Native Translation")
        case .google:
            return String(localized: "Google Translate")
        case .bing:
            return String(localized: "Bing Translate")
        case .youdao:
            return String(localized: "Youdao Translate")
        }
    }

    var subtitle: String {
        switch self {
        case .native:
            return String(localized: "System Translation")
        case .google:
            return String(localized: "Google web translation")
        case .bing:
            return String(localized: "Bing web translation")
        case .youdao:
            return String(localized: "Youdao web translation")
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var playWordPronunciation: Bool {
        didSet { defaults.set(playWordPronunciation, forKey: AppSettingKey.playWordPronunciation) }
    }
    @Published var playSentencePronunciation: Bool {
        didSet { defaults.set(playSentencePronunciation, forKey: AppSettingKey.playSentencePronunciation) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: AppSettingKey.launchAtLogin) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: AppSettingKey.showMenuBarIcon) }
    }

    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: AppSettingKey.showDockIcon) }
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
    @Published var sentenceTranslationSources: [SentenceTranslationSource] {
        didSet {
            saveSentenceTranslationSources()
        }
    }
    @Published var wordTTSProvider: TTSProvider {
        didSet { defaults.set(wordTTSProvider.rawValue, forKey: AppSettingKey.wordTTSProvider) }
    }
    @Published var sentenceTTSProvider: TTSProvider {
        didSet { defaults.set(sentenceTTSProvider.rawValue, forKey: AppSettingKey.sentenceTTSProvider) }
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
    @Published var sentenceTranslationEnabled: Bool {
        didSet { defaults.set(sentenceTranslationEnabled, forKey: AppSettingKey.sentenceTranslationEnabled) }
    }
    @Published var autoCheckUpdates: Bool {
        didSet {
            defaults.set(autoCheckUpdates, forKey: AppSettingKey.autoCheckUpdates)
        }
    }
    @Published var updateChannel: UpdateChannel {
        didSet {
            defaults.set(updateChannel.rawValue, forKey: AppSettingKey.updateChannel)
            UpdateChecker.shared.updateFeedURL()
        }
    }
    
    #if DEBUG
    /// Debug mode: force show update channel selector for testing
    @Published var debugShowChannelSelector: Bool {
        didSet {
            defaults.set(debugShowChannelSelector, forKey: AppSettingKey.debugShowChannelSelector)
        }
    }
    #endif

    private let defaults: UserDefaults
    private static let dictionarySourcesKey = "dictionarySources"
    private static let sentenceTranslationSourcesKey = "sentenceTranslationSources"

    init(defaults: UserDefaults = .standard, loginItemStatus: Bool? = nil) {
        self.defaults = defaults

        // Migration: check if old playPronunciation exists but new keys don't
        let hasOldKey = defaults.object(forKey: AppSettingKey.playPronunciation) != nil
        let hasNewKeys = defaults.object(forKey: AppSettingKey.playWordPronunciation) != nil
            || defaults.object(forKey: AppSettingKey.playSentencePronunciation) != nil

        if hasOldKey && !hasNewKeys {
            // Migrate from old single toggle to two separate toggles
            let oldValue = defaults.bool(forKey: AppSettingKey.playPronunciation)
            playWordPronunciation = oldValue
            playSentencePronunciation = oldValue
        } else {
            let playWordPronunciationValue = defaults.object(forKey: AppSettingKey.playWordPronunciation) as? Bool
            let playSentencePronunciationValue = defaults.object(forKey: AppSettingKey.playSentencePronunciation) as? Bool
            playWordPronunciation = playWordPronunciationValue ?? true
            playSentencePronunciation = playSentencePronunciationValue ?? true
        }

        let launchAtLoginValue = defaults.object(forKey: AppSettingKey.launchAtLogin) as? Bool
        let loginStatus = loginItemStatus ?? LoginItemManager.isEnabled()
        let showMenuBarIconValue = defaults.object(forKey: AppSettingKey.showMenuBarIcon) as? Bool
        let showDockIconValue = defaults.object(forKey: AppSettingKey.showDockIcon) as? Bool
        let singleKeyValue = defaults.string(forKey: AppSettingKey.singleKey)
        let debugShowOcrRegionValue = defaults.object(forKey: AppSettingKey.debugShowOcrRegion) as? Bool
        let continuousTranslationValue = defaults.object(forKey: AppSettingKey.continuousTranslation) as? Bool

        launchAtLogin = launchAtLoginValue ?? loginStatus
        showMenuBarIcon = showMenuBarIconValue ?? true
        showDockIcon = showDockIconValue ?? true
        singleKey = SingleKey(rawValue: singleKeyValue ?? "leftControl") ?? .leftControl
        sourceLanguage = defaults.string(forKey: AppSettingKey.sourceLanguage) ?? "en"
        let defaultTarget = Self.defaultTargetLanguage()
        targetLanguage = defaults.string(forKey: AppSettingKey.targetLanguage) ?? defaultTarget
        debugShowOcrRegion = debugShowOcrRegionValue ?? false
        continuousTranslation = continuousTranslationValue ?? true

        // Load or migrate dictionary sources
        dictionarySources = Self.loadOrMigrateDictionarySources(defaults: defaults)

        // Load sentence translation sources
        sentenceTranslationSources = Self.loadOrMigrateSentenceTranslationSources(defaults: defaults)

        // Load TTS providers with migration from old single ttsProvider
        let hasOldTTSKey = defaults.object(forKey: AppSettingKey.ttsProvider) != nil
        let hasNewTTSKeys = defaults.object(forKey: AppSettingKey.wordTTSProvider) != nil
            || defaults.object(forKey: AppSettingKey.sentenceTTSProvider) != nil

        if hasOldTTSKey && !hasNewTTSKeys {
            // Migrate from old single ttsProvider to two separate providers
            var oldProvider = defaults.string(forKey: AppSettingKey.ttsProvider)
            if oldProvider == "edge" { oldProvider = "bing" }
            let provider = TTSProvider(rawValue: oldProvider ?? "apple") ?? .apple
            wordTTSProvider = provider
            sentenceTTSProvider = provider
        } else {
            var wordProviderValue = defaults.string(forKey: AppSettingKey.wordTTSProvider)
            if wordProviderValue == "edge" { wordProviderValue = "bing" }
            wordTTSProvider = TTSProvider(rawValue: wordProviderValue ?? "apple") ?? .apple

            var sentenceProviderValue = defaults.string(forKey: AppSettingKey.sentenceTTSProvider)
            if sentenceProviderValue == "edge" { sentenceProviderValue = "bing" }
            sentenceTTSProvider = TTSProvider(rawValue: sentenceProviderValue ?? "apple") ?? .apple
        }
        
        // Load app language
        let appLanguageValue = defaults.string(forKey: AppSettingKey.appLanguage)
        appLanguage = AppLanguage(rawValue: appLanguageValue ?? "system") ?? .system
        
        // Load English accent preference
        let englishAccentValue = defaults.string(forKey: AppSettingKey.englishAccent)
        englishAccent = EnglishAccent(rawValue: englishAccentValue ?? "en-US") ?? .american
        
        // Load sentence translation enabled (default to true for backward compatibility)
        let sentenceTranslationEnabledValue = defaults.object(forKey: AppSettingKey.sentenceTranslationEnabled) as? Bool
        sentenceTranslationEnabled = sentenceTranslationEnabledValue ?? true

        // Load auto update settings
        let autoCheckUpdatesValue = defaults.object(forKey: AppSettingKey.autoCheckUpdates) as? Bool
        autoCheckUpdates = autoCheckUpdatesValue ?? true

        let updateChannelValue = defaults.string(forKey: AppSettingKey.updateChannel)
        updateChannel = UpdateChannel(rawValue: updateChannelValue ?? "stable") ?? .stable
        
        #if DEBUG
        // Load debug settings (default to false)
        let debugShowChannelSelectorValue = defaults.object(forKey: AppSettingKey.debugShowChannelSelector) as? Bool
        debugShowChannelSelector = debugShowChannelSelectorValue ?? false
        #endif
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
        ]
    }

    static func migrateDictionarySources(_ sources: [DictionarySource]) -> [DictionarySource] {
        sources.map {
            DictionarySource(
                id: $0.id,
                name: $0.type.displayName,
                type: $0.type,
                isEnabled: $0.isEnabled
            )
        }
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

    // MARK: - Sentence Translation Sources

    private func saveSentenceTranslationSources() {
        Self.persistSentenceTranslationSources(sentenceTranslationSources, defaults: defaults)
    }

    private static func loadOrMigrateSentenceTranslationSources(defaults: UserDefaults) -> [SentenceTranslationSource] {
        // Try to load existing sources
        if let data = defaults.data(forKey: sentenceTranslationSourcesKey),
           let sources = try? JSONDecoder().decode([SentenceTranslationSource].self, from: data) {
            return sources
        }

        let sources = defaultSentenceTranslationSources()
        persistSentenceTranslationSources(sources, defaults: defaults)
        return sources
    }

    private static func defaultSentenceTranslationSources() -> [SentenceTranslationSource] {
        if #available(macOS 15.0, *) {
            return [
                SentenceTranslationSource(id: UUID(), type: .native, isEnabled: true),
                SentenceTranslationSource(id: UUID(), type: .google, isEnabled: false),
                SentenceTranslationSource(id: UUID(), type: .bing, isEnabled: false),
                SentenceTranslationSource(id: UUID(), type: .youdao, isEnabled: false),
            ]
        } else {
            return [
                SentenceTranslationSource(id: UUID(), type: .native, isEnabled: false),
                SentenceTranslationSource(id: UUID(), type: .google, isEnabled: false),
                SentenceTranslationSource(id: UUID(), type: .bing, isEnabled: false),
                SentenceTranslationSource(id: UUID(), type: .youdao, isEnabled: true),
            ]
        }
    }

    private static func persistSentenceTranslationSources(
        _ sources: [SentenceTranslationSource],
        defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(sources) {
            defaults.set(data, forKey: sentenceTranslationSourcesKey)
        }
    }
}
