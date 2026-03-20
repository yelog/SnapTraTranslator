import Foundation

@MainActor
final class MacPrimaryTranslationProvider: PrimaryTranslationProviding {
    let bridge = TranslationBridge()

    func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        timeout: TimeInterval
    ) async throws -> String {
        try await bridge.translate(
            text: text,
            source: sourceLanguage.map(Locale.Language.init(identifier:)),
            target: Locale.Language(identifier: targetLanguage),
            timeout: timeout
        )
    }

    func translateBatch(
        texts: [String],
        sourceLanguage: String?,
        targetLanguage: String,
        timeout: TimeInterval
    ) async throws -> [String] {
        try await bridge.translateBatch(
            texts: texts,
            source: sourceLanguage.map(Locale.Language.init(identifier:)),
            target: Locale.Language(identifier: targetLanguage),
            timeout: timeout
        )
    }

    func cancelAllPendingRequests() {
        bridge.cancelAllPendingRequests()
    }
}
