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
protocol PrimaryTranslationProviding: AnyObject {
    func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        timeout: TimeInterval
    ) async throws -> String

    func translateBatch(
        texts: [String],
        sourceLanguage: String?,
        targetLanguage: String,
        timeout: TimeInterval
    ) async throws -> [String]

    func cancelAllPendingRequests()
}

@MainActor
protocol LanguageAvailabilityProviding: AnyObject {
    var isChecking: Bool { get }
    var isCheckingPublisher: AnyPublisher<Bool, Never> { get }
    var statusesPublisher: AnyPublisher<[String: LanguageAvailabilityStatus], Never> { get }

    func checkLanguagePair(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailabilityStatus
    func checkLanguagePairQuiet(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailabilityStatus
    func getStatus(from sourceLanguage: String, to targetLanguage: String) -> LanguageAvailabilityStatus?
    func openTranslationSettings()
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
