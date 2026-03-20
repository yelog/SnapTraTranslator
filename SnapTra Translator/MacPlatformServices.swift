import Foundation

enum MacPlatformServices {
    @MainActor
    static func make(permissions: PermissionManager) -> PlatformServices {
        PlatformServices(
            hotkey: HotkeyManager(),
            permissions: permissions,
            screenCapture: ScreenCaptureService(),
            ocr: OCRService(),
            dictionary: DictionaryService(),
            speech: SpeechService(),
            sentenceTranslation: SentenceTranslationService()
        )
    }
}
