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
        case openAI = "openai"
        case anthropic
        case gemini
        case deepSeek = "deepseek"
        case zhipu
        case ollama
        case omlx
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

struct LLMProviderConfiguration: Identifiable, Codable, Equatable {
    let provider: SentenceTranslationSource.SourceType
    var model: String
    var baseURL: String
    var zhipuRegion: ZhipuAPIRegion?

    var id: String {
        provider.rawValue
    }

    init(
        provider: SentenceTranslationSource.SourceType,
        model: String? = nil,
        baseURL: String? = nil,
        zhipuRegion: ZhipuAPIRegion? = nil
    ) {
        self.provider = provider
        let resolvedZhipuRegion = provider == .zhipu
            ? (zhipuRegion ?? ZhipuAPIRegion.region(for: baseURL) ?? .domestic)
            : nil
        self.model = model ?? provider.defaultLLMModel
        self.baseURL = baseURL ?? provider.defaultLLMBaseURL(region: resolvedZhipuRegion)
        self.zhipuRegion = resolvedZhipuRegion
    }

    static func defaultConfiguration(
        for provider: SentenceTranslationSource.SourceType
    ) -> LLMProviderConfiguration {
        LLMProviderConfiguration(provider: provider)
    }
}

enum ZhipuAPIRegion: String, CaseIterable, Codable, Equatable {
    case domestic
    case international

    var displayName: String {
        switch self {
        case .domestic:
            return String(localized: "China")
        case .international:
            return String(localized: "Global")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .domestic:
            return "https://open.bigmodel.cn/api/paas/v4"
        case .international:
            return "https://api.z.ai/api/paas/v4"
        }
    }

    static func region(for baseURL: String?) -> ZhipuAPIRegion? {
        guard let baseURL else { return nil }

        let normalizedURL = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedURL.contains("api.z.ai") {
            return .international
        }
        if normalizedURL.contains("open.bigmodel.cn") {
            return .domestic
        }
        return nil
    }
}

extension SentenceTranslationSource.SourceType {
    static let llmProviderTypes: [Self] = [
        .openAI,
        .anthropic,
        .gemini,
        .deepSeek,
        .zhipu,
        .ollama,
        .omlx,
    ]

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
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        case .deepSeek:
            return "DeepSeek"
        case .zhipu:
            return "智谱"
        case .ollama:
            return "Ollama"
        case .omlx:
            return "oMLX"
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
        case .openAI:
            return String(localized: "OpenAI API translation")
        case .anthropic:
            return String(localized: "Claude API translation")
        case .gemini:
            return String(localized: "Gemini API translation")
        case .deepSeek:
            return String(localized: "DeepSeek API translation")
        case .zhipu:
            return String(localized: "Zhipu API translation")
        case .ollama:
            return String(localized: "Local Ollama translation")
        case .omlx:
            return String(localized: "Local oMLX translation")
        }
    }

    var isLLMProvider: Bool {
        Self.llmProviderTypes.contains(self)
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .anthropic, .gemini, .deepSeek, .zhipu:
            return true
        case .native, .google, .bing, .youdao, .ollama, .omlx:
            return false
        }
    }

    var acceptsOptionalAPIKey: Bool {
        switch self {
        case .ollama, .omlx:
            return true
        case .native, .google, .bing, .youdao, .openAI, .anthropic, .gemini, .deepSeek, .zhipu:
            return false
        }
    }

    var defaultLLMModel: String {
        switch self {
        case .openAI:
            return "gpt-4.1-mini"
        case .anthropic:
            return "claude-haiku-4-5"
        case .gemini:
            return "gemini-3.5-flash"
        case .deepSeek:
            return "deepseek-v4-flash"
        case .zhipu:
            return "glm-4.7-flash"
        case .ollama:
            return "gpt-oss:20b"
        case .omlx:
            return "qwen3.5"
        case .native, .google, .bing, .youdao:
            return ""
        }
    }

    var defaultLLMBaseURL: String {
        defaultLLMBaseURL(region: nil)
    }

    func defaultLLMBaseURL(region: ZhipuAPIRegion?) -> String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .anthropic:
            return "https://api.anthropic.com/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        case .deepSeek:
            return "https://api.deepseek.com"
        case .zhipu:
            return (region ?? .domestic).defaultBaseURL
        case .ollama:
            return "http://localhost:11434/v1"
        case .omlx:
            return "http://localhost:8000/v1"
        case .native, .google, .bing, .youdao:
            return ""
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
    @Published var copyWord: Bool {
        didSet { defaults.set(copyWord, forKey: AppSettingKey.copyWord) }
    }
    @Published var copySentence: Bool {
        didSet { defaults.set(copySentence, forKey: AppSettingKey.copySentence) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: AppSettingKey.launchAtLogin) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: AppSettingKey.showMenuBarIcon) }
    }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: AppSettingKey.menuBarIconStyle) }
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
    @Published var bidirectionalTranslationEnabled: Bool {
        didSet { defaults.set(bidirectionalTranslationEnabled, forKey: AppSettingKey.bidirectionalTranslationEnabled) }
    }
    @Published var debugShowOcrRegion: Bool {
        didSet { defaults.set(debugShowOcrRegion, forKey: AppSettingKey.debugShowOcrRegion) }
    }
    @Published var continuousTranslation: Bool {
        didSet { defaults.set(continuousTranslation, forKey: AppSettingKey.continuousTranslation) }
    }
    @Published var keepWordOverlayAfterTap: Bool {
        didSet { defaults.set(keepWordOverlayAfterTap, forKey: AppSettingKey.keepWordOverlayAfterTap) }
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
    @Published var llmProviderConfigurations: [LLMProviderConfiguration] {
        didSet {
            saveLLMProviderConfigurations()
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
    @Published var ocrSentenceTranslationEnabled: Bool {
        didSet { defaults.set(ocrSentenceTranslationEnabled, forKey: AppSettingKey.ocrSentenceTranslationEnabled) }
    }
    @Published var doubleTapSentenceTranslationMode: DoubleTapSentenceTranslationMode {
        didSet {
            defaults.set(
                doubleTapSentenceTranslationMode.rawValue,
                forKey: AppSettingKey.doubleTapSentenceTranslationMode
            )
        }
    }
    @Published var selectedTextTranslationEnabled: Bool {
        didSet { defaults.set(selectedTextTranslationEnabled, forKey: AppSettingKey.selectedTextTranslationEnabled) }
    }
    @Published var hideOriginalTextInSentenceOverlay: Bool {
        didSet { defaults.set(hideOriginalTextInSentenceOverlay, forKey: AppSettingKey.hideOriginalTextInSentenceOverlay) }
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

    @Published var learningMaxRecords: Int {
        didSet { defaults.set(learningMaxRecords, forKey: AppSettingKey.learningMaxRecords) }
    }
    @Published var learningCleanupDays: Int {
        didSet { defaults.set(learningCleanupDays, forKey: AppSettingKey.learningCleanupDays) }
    }
    @Published var learningAutoCleanup: Bool {
        didSet { defaults.set(learningAutoCleanup, forKey: AppSettingKey.learningAutoCleanup) }
    }

    private let defaults: UserDefaults
    private static let dictionarySourcesKey = "dictionarySources"
    private static let sentenceTranslationSourcesKey = "sentenceTranslationSources"
    private static let llmProviderConfigurationsKey = "llmProviderConfigurations"

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
            playSentencePronunciation = playSentencePronunciationValue ?? false
        }

        let copyWordValue = defaults.object(forKey: AppSettingKey.copyWord) as? Bool
        let copySentenceValue = defaults.object(forKey: AppSettingKey.copySentence) as? Bool
        copyWord = copyWordValue ?? false
        copySentence = copySentenceValue ?? false

        let launchAtLoginValue = defaults.object(forKey: AppSettingKey.launchAtLogin) as? Bool
        let loginStatus = loginItemStatus ?? LoginItemManager.isEnabled()
        let showMenuBarIconValue = defaults.object(forKey: AppSettingKey.showMenuBarIcon) as? Bool
        let menuBarIconStyleValue = defaults.string(forKey: AppSettingKey.menuBarIconStyle)
        let showDockIconValue = defaults.object(forKey: AppSettingKey.showDockIcon) as? Bool
        let singleKeyValue = defaults.string(forKey: AppSettingKey.singleKey)
        let debugShowOcrRegionValue = defaults.object(forKey: AppSettingKey.debugShowOcrRegion) as? Bool
        let continuousTranslationValue = defaults.object(forKey: AppSettingKey.continuousTranslation) as? Bool
        let keepWordOverlayAfterTapValue = defaults.object(forKey: AppSettingKey.keepWordOverlayAfterTap) as? Bool

        launchAtLogin = launchAtLoginValue ?? loginStatus
        showMenuBarIcon = showMenuBarIconValue ?? true
        menuBarIconStyle = MenuBarIconStyle(rawValue: menuBarIconStyleValue ?? "auto") ?? .auto
        showDockIcon = showDockIconValue ?? true
        singleKey = SingleKey(rawValue: singleKeyValue ?? "leftControl") ?? .leftControl
        sourceLanguage = defaults.string(forKey: AppSettingKey.sourceLanguage) ?? "en"
        let defaultTarget = Self.defaultTargetLanguage()
        targetLanguage = defaults.string(forKey: AppSettingKey.targetLanguage) ?? defaultTarget
        bidirectionalTranslationEnabled = Self.loadBidirectionalTranslationEnabled(defaults: defaults)
        debugShowOcrRegion = debugShowOcrRegionValue ?? false
        continuousTranslation = continuousTranslationValue ?? true
        keepWordOverlayAfterTap = keepWordOverlayAfterTapValue ?? true

        // Load or migrate dictionary sources
        dictionarySources = Self.loadOrMigrateDictionarySources(defaults: defaults)

        // Load sentence translation sources
        sentenceTranslationSources = Self.loadOrMigrateSentenceTranslationSources(defaults: defaults)
        llmProviderConfigurations = Self.loadOrMigrateLLMProviderConfigurations(defaults: defaults)

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
        
        let sentenceTranslationSettings = Self.loadSentenceTranslationSettings(defaults: defaults)
        ocrSentenceTranslationEnabled = sentenceTranslationSettings.ocrSentenceTranslationEnabled
        let doubleTapModeValue = defaults.string(forKey: AppSettingKey.doubleTapSentenceTranslationMode)
        doubleTapSentenceTranslationMode = DoubleTapSentenceTranslationMode(
            rawValue: doubleTapModeValue ?? ""
        ) ?? .cursorParagraph
        selectedTextTranslationEnabled = sentenceTranslationSettings.selectedTextTranslationEnabled
        let hideOriginalTextValue = defaults.object(forKey: AppSettingKey.hideOriginalTextInSentenceOverlay) as? Bool
        hideOriginalTextInSentenceOverlay = hideOriginalTextValue ?? true

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

        // Load learning cleanup settings
        let learningMaxRecordsValue = defaults.object(forKey: AppSettingKey.learningMaxRecords) as? Int
        learningMaxRecords = learningMaxRecordsValue ?? 5000

        let learningCleanupDaysValue = defaults.object(forKey: AppSettingKey.learningCleanupDays) as? Int
        learningCleanupDays = learningCleanupDaysValue ?? 90

        let learningAutoCleanupValue = defaults.object(forKey: AppSettingKey.learningAutoCleanup) as? Bool
        learningAutoCleanup = learningAutoCleanupValue ?? true
        
        // Persist all settings to UserDefaults since didSet is NOT called during init
        persistAllSettings()
    }
    
    private func persistAllSettings() {
        defaults.set(playWordPronunciation, forKey: AppSettingKey.playWordPronunciation)
        defaults.set(playSentencePronunciation, forKey: AppSettingKey.playSentencePronunciation)
        defaults.set(copyWord, forKey: AppSettingKey.copyWord)
        defaults.set(copySentence, forKey: AppSettingKey.copySentence)
        defaults.set(launchAtLogin, forKey: AppSettingKey.launchAtLogin)
        defaults.set(showMenuBarIcon, forKey: AppSettingKey.showMenuBarIcon)
        defaults.set(menuBarIconStyle.rawValue, forKey: AppSettingKey.menuBarIconStyle)
        defaults.set(showDockIcon, forKey: AppSettingKey.showDockIcon)
        defaults.set(singleKey.rawValue, forKey: AppSettingKey.singleKey)
        defaults.set(sourceLanguage, forKey: AppSettingKey.sourceLanguage)
        defaults.set(targetLanguage, forKey: AppSettingKey.targetLanguage)
        defaults.set(bidirectionalTranslationEnabled, forKey: AppSettingKey.bidirectionalTranslationEnabled)
        defaults.set(debugShowOcrRegion, forKey: AppSettingKey.debugShowOcrRegion)
        defaults.set(continuousTranslation, forKey: AppSettingKey.continuousTranslation)
        defaults.set(keepWordOverlayAfterTap, forKey: AppSettingKey.keepWordOverlayAfterTap)
        defaults.set(wordTTSProvider.rawValue, forKey: AppSettingKey.wordTTSProvider)
        defaults.set(sentenceTTSProvider.rawValue, forKey: AppSettingKey.sentenceTTSProvider)
        defaults.set(appLanguage.rawValue, forKey: AppSettingKey.appLanguage)
        defaults.set(englishAccent.rawValue, forKey: AppSettingKey.englishAccent)
        defaults.set(ocrSentenceTranslationEnabled, forKey: AppSettingKey.ocrSentenceTranslationEnabled)
        defaults.set(
            doubleTapSentenceTranslationMode.rawValue,
            forKey: AppSettingKey.doubleTapSentenceTranslationMode
        )
        defaults.set(selectedTextTranslationEnabled, forKey: AppSettingKey.selectedTextTranslationEnabled)
        defaults.set(hideOriginalTextInSentenceOverlay, forKey: AppSettingKey.hideOriginalTextInSentenceOverlay)
        defaults.set(autoCheckUpdates, forKey: AppSettingKey.autoCheckUpdates)
        defaults.set(updateChannel.rawValue, forKey: AppSettingKey.updateChannel)
        #if DEBUG
        defaults.set(debugShowChannelSelector, forKey: AppSettingKey.debugShowChannelSelector)
        #endif
        defaults.set(learningMaxRecords, forKey: AppSettingKey.learningMaxRecords)
        defaults.set(learningCleanupDays, forKey: AppSettingKey.learningCleanupDays)
        defaults.set(learningAutoCleanup, forKey: AppSettingKey.learningAutoCleanup)
        saveDictionarySources()
        saveSentenceTranslationSources()
        saveLLMProviderConfigurations()
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
        defaultDictionarySourceDefinitions(ecdictInstalled: ecdictInstalled).map { definition in
            makeDictionarySource(type: definition.type, isEnabled: definition.isEnabled)
        }
    }

    static func migrateDictionarySources(_ sources: [DictionarySource]) -> [DictionarySource] {
        var migrated = sources.map {
            DictionarySource(
                id: $0.id,
                name: $0.type.displayName,
                type: $0.type,
                isEnabled: $0.isEnabled
            )
        }

        let existingTypes = Set(migrated.map(\.type))
        for definition in defaultDictionarySourceDefinitions(ecdictInstalled: isECDICTInstalled)
            where !existingTypes.contains(definition.type) {
            migrated.append(
                makeDictionarySource(
                    type: definition.type,
                    isEnabled: definition.isEnabled
                )
            )
        }

        return migrated
    }

    private static func defaultDictionarySources() -> [DictionarySource] {
        defaultDictionarySources(ecdictInstalled: isECDICTInstalled)
    }

    private static func defaultDictionarySourceDefinitions(
        ecdictInstalled: Bool
    ) -> [(type: DictionarySource.SourceType, isEnabled: Bool)] {
        [
            (.system, true),
            (.ecdict, ecdictInstalled),
            (.youdao, false),
            (.google, false),
            (.freeDictionaryAPI, false),
        ]
    }

    static func loadSentenceTranslationSettings(
        defaults: UserDefaults
    ) -> (ocrSentenceTranslationEnabled: Bool, selectedTextTranslationEnabled: Bool) {
        let ocrSentenceTranslationEnabledValue = defaults.object(
            forKey: AppSettingKey.ocrSentenceTranslationEnabled
        ) as? Bool
        let legacySentenceTranslationEnabledValue = defaults.object(
            forKey: AppSettingKey.legacySentenceTranslationEnabled
        ) as? Bool
        let resolvedOcrSentenceTranslationEnabled = ocrSentenceTranslationEnabledValue
            ?? legacySentenceTranslationEnabledValue
            ?? true
        let selectedTextTranslationEnabled = defaults.object(
            forKey: AppSettingKey.selectedTextTranslationEnabled
        ) as? Bool ?? true

        if ocrSentenceTranslationEnabledValue == nil {
            defaults.set(
                resolvedOcrSentenceTranslationEnabled,
                forKey: AppSettingKey.ocrSentenceTranslationEnabled
            )
        }

        return (
            ocrSentenceTranslationEnabled: resolvedOcrSentenceTranslationEnabled,
            selectedTextTranslationEnabled: selectedTextTranslationEnabled
        )
    }

    static func loadBidirectionalTranslationEnabled(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppSettingKey.bidirectionalTranslationEnabled) as? Bool ?? true
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

    private func saveLLMProviderConfigurations() {
        Self.persistLLMProviderConfigurations(llmProviderConfigurations, defaults: defaults)
    }

    private static func loadOrMigrateSentenceTranslationSources(defaults: UserDefaults) -> [SentenceTranslationSource] {
        // Try to load existing sources
        if let data = defaults.data(forKey: sentenceTranslationSourcesKey),
           let sources = try? JSONDecoder().decode([SentenceTranslationSource].self, from: data) {
            let migrated = migrateSentenceTranslationSources(sources)
            persistSentenceTranslationSources(migrated, defaults: defaults)
            return migrated
        }

        let sources = defaultSentenceTranslationSources()
        persistSentenceTranslationSources(sources, defaults: defaults)
        return sources
    }

    static func migrateSentenceTranslationSources(
        _ sources: [SentenceTranslationSource]
    ) -> [SentenceTranslationSource] {
        var migrated: [SentenceTranslationSource] = []
        var seenTypes = Set<SentenceTranslationSource.SourceType>()

        for source in sources where !seenTypes.contains(source.type) {
            migrated.append(source)
            seenTypes.insert(source.type)
        }

        for definition in defaultSentenceTranslationSourceDefinitions()
            where !seenTypes.contains(definition.type) {
            migrated.append(
                SentenceTranslationSource(
                    id: UUID(),
                    type: definition.type,
                    isEnabled: definition.isEnabled
                )
            )
        }

        return migrated
    }

    private static func defaultSentenceTranslationSources() -> [SentenceTranslationSource] {
        defaultSentenceTranslationSourceDefinitions().map {
            SentenceTranslationSource(id: UUID(), type: $0.type, isEnabled: $0.isEnabled)
        }
    }

    private static func defaultSentenceTranslationSourceDefinitions() -> [
        (type: SentenceTranslationSource.SourceType, isEnabled: Bool)
    ] {
        if #available(macOS 15.0, *) {
            return [
                (.native, true),
                (.google, false),
                (.bing, false),
                (.youdao, false),
                (.openAI, false),
                (.anthropic, false),
                (.gemini, false),
                (.deepSeek, false),
                (.zhipu, false),
                (.ollama, false),
                (.omlx, false),
            ]
        } else {
            return [
                (.native, false),
                (.google, false),
                (.bing, false),
                (.youdao, true),
                (.openAI, false),
                (.anthropic, false),
                (.gemini, false),
                (.deepSeek, false),
                (.zhipu, false),
                (.ollama, false),
                (.omlx, false),
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

    private static func persistLLMProviderConfigurations(
        _ configurations: [LLMProviderConfiguration],
        defaults: UserDefaults
    ) {
        if let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: llmProviderConfigurationsKey)
        }
    }

    private static func loadOrMigrateLLMProviderConfigurations(
        defaults: UserDefaults
    ) -> [LLMProviderConfiguration] {
        if let data = defaults.data(forKey: llmProviderConfigurationsKey),
           let configurations = try? JSONDecoder().decode([LLMProviderConfiguration].self, from: data) {
            let migrated = migrateLLMProviderConfigurations(configurations)
            persistLLMProviderConfigurations(migrated, defaults: defaults)
            return migrated
        }

        let configurations = defaultLLMProviderConfigurations()
        persistLLMProviderConfigurations(configurations, defaults: defaults)
        return configurations
    }

    static func migrateLLMProviderConfigurations(
        _ configurations: [LLMProviderConfiguration]
    ) -> [LLMProviderConfiguration] {
        var result: [LLMProviderConfiguration] = []
        var seenTypes = Set<SentenceTranslationSource.SourceType>()

        for provider in SentenceTranslationSource.SourceType.llmProviderTypes {
            let existing = configurations.first {
                $0.provider == provider && !seenTypes.contains($0.provider)
            }
            let configuration = existing ?? LLMProviderConfiguration.defaultConfiguration(for: provider)
            let zhipuRegion = provider == .zhipu
                ? (configuration.zhipuRegion ?? ZhipuAPIRegion.region(for: configuration.baseURL) ?? .domestic)
                : nil
            result.append(
                LLMProviderConfiguration(
                    provider: provider,
                    model: configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? provider.defaultLLMModel
                        : configuration.model,
                    baseURL: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? provider.defaultLLMBaseURL(region: zhipuRegion)
                        : configuration.baseURL,
                    zhipuRegion: zhipuRegion
                )
            )
            seenTypes.insert(provider)
        }

        return result
    }

    static func defaultLLMProviderConfigurations() -> [LLMProviderConfiguration] {
        SentenceTranslationSource.SourceType.llmProviderTypes.map {
            LLMProviderConfiguration.defaultConfiguration(for: $0)
        }
    }

    func llmProviderConfiguration(
        for provider: SentenceTranslationSource.SourceType
    ) -> LLMProviderConfiguration {
        guard provider.isLLMProvider else {
            return LLMProviderConfiguration(provider: provider)
        }

        return llmProviderConfigurations.first { $0.provider == provider }
            ?? LLMProviderConfiguration.defaultConfiguration(for: provider)
    }

    func updateLLMProviderConfiguration(
        for provider: SentenceTranslationSource.SourceType,
        model: String,
        baseURL: String,
        zhipuRegion: ZhipuAPIRegion? = nil
    ) {
        guard provider.isLLMProvider else { return }

        var configurations = llmProviderConfigurations
        let currentConfiguration = llmProviderConfiguration(for: provider)
        let resolvedZhipuRegion = provider == .zhipu
            ? (zhipuRegion ?? currentConfiguration.zhipuRegion ?? ZhipuAPIRegion.region(for: baseURL) ?? .domestic)
            : nil
        let configuration = LLMProviderConfiguration(
            provider: provider,
            model: model,
            baseURL: baseURL,
            zhipuRegion: resolvedZhipuRegion
        )

        if let index = configurations.firstIndex(where: { $0.provider == provider }) {
            configurations[index] = configuration
        } else {
            configurations.append(configuration)
        }

        llmProviderConfigurations = Self.migrateLLMProviderConfigurations(configurations)
    }

    func resetLLMProviderConfiguration(for provider: SentenceTranslationSource.SourceType) {
        guard provider.isLLMProvider else { return }

        updateLLMProviderConfiguration(
            for: provider,
            model: provider.defaultLLMModel,
            baseURL: provider.defaultLLMBaseURL,
            zhipuRegion: provider == .zhipu ? .domestic : nil
        )
    }
}
