import Combine
import Foundation

@MainActor
final class TranslationEngineManager: ObservableObject {
    @Published private(set) var currentEngine: (any TranslationEngine)?
    @Published var selectedEngineType: TranslationEngineType = .apple {
        didSet {
            switchEngine(to: selectedEngineType)
        }
    }

    private var engines: [TranslationEngineType: any TranslationEngine] = [:]
    private var configurations: EngineConfigurations
    private weak var translationBridge: TranslationBridge?

    init(bridge: TranslationBridge, configurations: EngineConfigurations) {
        self.translationBridge = bridge
        self.configurations = configurations
        initializeEngines()
        switchEngine(to: selectedEngineType)
    }

    private func initializeEngines() {
        // Apple engine (requires macOS 15+)
        if #available(macOS 15.0, *), let bridge = translationBridge {
            engines[.apple] = AppleTranslationEngine(bridge: bridge)
        }

        // Third-party engines
        engines[.google] = GoogleTranslationEngine(config: configurations.google)
        engines[.bing] = BingTranslationEngine(config: configurations.bing)
        engines[.baidu] = BaiduTranslationEngine(config: configurations.baidu)
        engines[.youdao] = YoudaoTranslationEngine(config: configurations.youdao)
    }

    func switchEngine(to type: TranslationEngineType) {
        currentEngine = engines[type]
    }

    func updateConfiguration(for type: TranslationEngineType, config: EngineAPIConfig) {
        configurations[type] = config

        switch type {
        case .google:
            (engines[.google] as? GoogleTranslationEngine)?.updateConfig(config)
        case .bing:
            (engines[.bing] as? BingTranslationEngine)?.updateConfig(config)
        case .baidu:
            (engines[.baidu] as? BaiduTranslationEngine)?.updateConfig(config)
        case .youdao:
            (engines[.youdao] as? YoudaoTranslationEngine)?.updateConfig(config)
        case .apple:
            break
        }
    }

    func getConfiguration(for type: TranslationEngineType) -> EngineAPIConfig {
        return configurations[type]
    }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult {
        guard let engine = currentEngine else {
            throw TranslationEngineError.engineNotAvailable
        }
        return try await engine.translate(text: text, from: sourceLanguage, to: targetLanguage)
    }

    func getAudioURL(for text: String, language: String) -> URL? {
        return currentEngine?.getAudioURL(for: text, language: language)
    }

    func supportsLanguagePair(from: String, to: String) async -> Bool {
        guard let engine = currentEngine else { return false }
        return await engine.supportsLanguagePair(from: from, to: to)
    }
}
