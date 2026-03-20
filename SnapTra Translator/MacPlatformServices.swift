import Foundation

enum MacPlatformServices {
    @MainActor
    static func make(permissions: PermissionManager) -> PlatformServices {
        let languageAvailability: (any LanguageAvailabilityProviding)?
        if #available(macOS 15.0, *) {
            languageAvailability = MacLanguageAvailabilityProvider()
        } else {
            languageAvailability = nil
        }

        return PlatformServices(
            hotkey: HotkeyManager(),
            permissions: permissions,
            screenCapture: ScreenCaptureService(),
            ocr: OCRService(),
            dictionary: DictionaryService(),
            primaryTranslation: MacPrimaryTranslationProvider(),
            speech: SpeechService(),
            sentenceTranslation: SentenceTranslationService(),
            languageAvailability: languageAvailability
        )
    }
}
