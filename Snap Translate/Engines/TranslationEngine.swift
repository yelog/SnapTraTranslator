import Foundation

/// Translation engine type enumeration
enum TranslationEngineType: String, CaseIterable, Identifiable, Codable {
    case apple = "apple"
    case google = "google"
    case bing = "bing"
    case baidu = "baidu"
    case youdao = "youdao"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple (Built-in)"
        case .google: return "Google Translate"
        case .bing: return "Bing Translator"
        case .baidu: return "Baidu Translate"
        case .youdao: return "Youdao Dictionary"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .apple: return false
        case .baidu: return true
        case .google, .bing, .youdao: return false
        }
    }

    var supportsCustomAPIKey: Bool {
        switch self {
        case .apple: return false
        case .google, .bing, .baidu, .youdao: return true
        }
    }

    var apiKeyURL: URL {
        switch self {
        case .apple: return URL(string: "https://apple.com")!
        case .google: return URL(string: "https://console.cloud.google.com/apis/credentials")!
        case .bing: return URL(string: "https://portal.azure.com/#create/Microsoft.CognitiveServicesTextTranslation")!
        case .baidu: return URL(string: "https://fanyi-api.baidu.com/manage/developer")!
        case .youdao: return URL(string: "https://ai.youdao.com/console/")!
        }
    }
}

/// Translation result containing complete dictionary information
struct TranslationResult {
    let word: String
    let phonetic: String?
    let translation: String
    let definitions: [DictionaryEntry.Definition]
    let audioURL: URL?

    init(
        word: String,
        phonetic: String? = nil,
        translation: String,
        definitions: [DictionaryEntry.Definition] = [],
        audioURL: URL? = nil
    ) {
        self.word = word
        self.phonetic = phonetic
        self.translation = translation
        self.definitions = definitions
        self.audioURL = audioURL
    }
}

/// Translation engine protocol
protocol TranslationEngine {
    var engineType: TranslationEngineType { get }
    var usesCustomAPIKey: Bool { get }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult

    func getAudioURL(for text: String, language: String) -> URL?

    func supportsLanguagePair(from: String, to: String) async -> Bool
}

extension TranslationEngine {
    func supportsLanguagePair(from: String, to: String) async -> Bool {
        return true
    }

    func getAudioURL(for text: String, language: String) -> URL? {
        return nil
    }
}

/// Translation engine errors
enum TranslationEngineError: LocalizedError {
    case networkError(Error)
    case apiKeyRequired
    case invalidAPIKey
    case unsupportedLanguagePair
    case rateLimitExceeded
    case parseError
    case timeout
    case emptyResponse
    case engineNotAvailable

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiKeyRequired:
            return "API key is required for this service"
        case .invalidAPIKey:
            return "Invalid API key"
        case .unsupportedLanguagePair:
            return "Language pair not supported"
        case .rateLimitExceeded:
            return "Rate limit exceeded, please try again later"
        case .parseError:
            return "Failed to parse response"
        case .timeout:
            return "Request timeout"
        case .emptyResponse:
            return "Empty response from server"
        case .engineNotAvailable:
            return "Translation engine not available"
        }
    }
}
