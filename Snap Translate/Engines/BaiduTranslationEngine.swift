import CryptoKit
import Foundation

final class BaiduTranslationEngine: TranslationEngine {
    let engineType: TranslationEngineType = .baidu
    var usesCustomAPIKey: Bool { config.useCustomAPI }

    private var config: EngineAPIConfig
    private let session: URLSession

    init(config: EngineAPIConfig = EngineAPIConfig()) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: configuration)
    }

    func updateConfig(_ config: EngineAPIConfig) {
        self.config = config
    }

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult {
        // Baidu requires API key
        guard !config.appId.isEmpty && !config.secretKey.isEmpty else {
            throw TranslationEngineError.apiKeyRequired
        }

        let salt = String(Int.random(in: 10000...99999))
        let sign = md5("\(config.appId)\(text)\(salt)\(config.secretKey)")

        let baiduFrom = convertToBaiduLanguageCode(sourceLanguage)
        let baiduTo = convertToBaiduLanguageCode(targetLanguage)

        var components = URLComponents(string: "https://fanyi-api.baidu.com/api/trans/vip/translate")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: baiduFrom),
            URLQueryItem(name: "to", value: baiduTo),
            URLQueryItem(name: "appid", value: config.appId),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign)
        ]

        guard let url = components.url else {
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        return try parseBaiduResponse(data, originalText: text, sourceLanguage: sourceLanguage)
    }

    private func parseBaiduResponse(
        _ data: Data,
        originalText: String,
        sourceLanguage: String
    ) throws -> TranslationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationEngineError.parseError
        }

        // Check for errors
        if let errorCode = json["error_code"] as? String {
            switch errorCode {
            case "54003":
                throw TranslationEngineError.rateLimitExceeded
            case "52001", "52002", "52003":
                throw TranslationEngineError.networkError(URLError(.timedOut))
            case "54001", "54004":
                throw TranslationEngineError.invalidAPIKey
            default:
                throw TranslationEngineError.parseError
            }
        }

        guard let transResult = json["trans_result"] as? [[String: Any]],
              let first = transResult.first,
              let translatedText = first["dst"] as? String else {
            throw TranslationEngineError.parseError
        }

        return TranslationResult(
            word: originalText,
            phonetic: nil,
            translation: translatedText,
            definitions: [],
            audioURL: getAudioURL(for: originalText, language: sourceLanguage)
        )
    }

    private func convertToBaiduLanguageCode(_ code: String) -> String {
        switch code {
        case "zh-Hans", "zh-Hant": return "zh"
        case "en": return "en"
        case "ja": return "jp"
        case "ko": return "kor"
        case "fr": return "fra"
        case "de": return "de"
        case "es": return "spa"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ara"
        case "th": return "th"
        case "vi": return "vie"
        default: return code
        }
    }

    private func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    func getAudioURL(for text: String, language: String) -> URL? {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let langCode = convertToBaiduLanguageCode(language)
        return URL(string: "https://fanyi.baidu.com/gettts?lan=\(langCode)&text=\(encodedText)&spd=3&source=web")
    }
}
