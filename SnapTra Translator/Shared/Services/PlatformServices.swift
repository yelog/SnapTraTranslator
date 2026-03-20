import Foundation

struct PlatformServices {
    let hotkey: any HotkeyControlling
    let permissions: any PermissionProviding
    let screenCapture: any ScreenCaptureProviding
    let ocr: any OCRProviding
    let dictionary: any DictionaryProviding
    let speech: any SpeechProviding
    let sentenceTranslation: any SentenceTranslationProviding
}
