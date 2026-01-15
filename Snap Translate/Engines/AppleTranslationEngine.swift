import Foundation
import Translation

@available(macOS 15.0, *)
final class AppleTranslationEngine: TranslationEngine {
    let engineType: TranslationEngineType = .apple
    let usesCustomAPIKey: Bool = false

    private let bridge: TranslationBridge
    private let dictionaryService = DictionaryService()

    init(bridge: TranslationBridge) {
        self.bridge = bridge
    }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult {
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)

        // Get dictionary entry for phonetic and definitions
        let dictEntry = dictionaryService.lookup(text)
        let phonetic = dictEntry?.phonetic
        var definitions = dictEntry?.definitions ?? []

        // Translate the word
        let translated = try await bridge.translate(
            text: text,
            source: source,
            target: target
        )

        // Translate definitions if available
        if !definitions.isEmpty {
            var translatedDefs: [DictionaryEntry.Definition] = []
            for def in definitions.prefix(3) {
                if let meaningTranslation = try? await bridge.translate(
                    text: def.meaning,
                    source: source,
                    target: target
                ) {
                    translatedDefs.append(DictionaryEntry.Definition(
                        partOfSpeech: def.partOfSpeech,
                        meaning: def.meaning,
                        translation: meaningTranslation,
                        examples: def.examples
                    ))
                } else {
                    translatedDefs.append(def)
                }
            }
            definitions = translatedDefs
        }

        return TranslationResult(
            word: text,
            phonetic: phonetic,
            translation: translated,
            definitions: definitions,
            audioURL: nil
        )
    }

    func getAudioURL(for text: String, language: String) -> URL? {
        return nil
    }

    func supportsLanguagePair(from: String, to: String) async -> Bool {
        let availability = LanguageAvailability()
        let source = Locale.Language(identifier: from)
        let target = Locale.Language(identifier: to)
        let status = await availability.status(from: source, to: target)
        return status == .installed || status == .supported
    }
}
