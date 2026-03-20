import Combine
import CoreGraphics
import Foundation

@MainActor
protocol HotkeyControlling: AnyObject {
    var onTrigger: (() -> Void)? { get set }
    var onRelease: (() -> Void)? { get set }
    var onDoubleTap: (() -> Void)? { get set }

    func start(singleKey: SingleKey)
    func stop()
}

@MainActor
protocol PermissionProviding: AnyObject {
    var status: PermissionStatus { get }
    var statusPublisher: AnyPublisher<PermissionStatus, Never> { get }

    func refreshStatus()
    func refreshStatusAsync() async
    func requestScreenRecording()
    func requestAndOpenScreenRecording()
    func openScreenRecordingSettings()
}

@MainActor
protocol ScreenCaptureProviding: AnyObject {
    func captureAroundCursor() async -> (image: CGImage, region: CaptureRegion)?
    func captureCurrentDisplay() async -> (image: CGImage, region: CaptureRegion)?
    func invalidateCache()
}

protocol OCRProviding: AnyObject {
    func recognizeWords(in image: CGImage, language: String) async throws -> [RecognizedWord]
    func recognizeParagraphsWithRawLines(
        in image: CGImage,
        language: String
    ) async throws -> (paragraphs: [RecognizedParagraph], lines: [RecognizedTextLine])
}

protocol DictionaryProviding: AnyObject {
    var offlineService: OfflineDictionaryService { get }

    func lookupSingle(
        _ word: String,
        source: DictionarySource,
        sourceLanguage: String,
        targetLanguage: String,
        preferEnglish: Bool
    ) async -> DictionaryEntry?
}

protocol SentenceTranslationProviding: AnyObject {
    func translate(
        text: String,
        provider: SentenceTranslationSource.SourceType,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String?
}

@MainActor
protocol SpeechProviding: AnyObject {
    func speak(
        _ text: String,
        language: String?,
        provider: TTSProvider,
        useAmericanAccent: Bool
    )

    func stopSpeaking()
}
