import Foundation

final class BingTranslationEngine: TranslationEngine {
    let engineType: TranslationEngineType = .bing
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
        if config.useCustomAPI && !config.apiKey.isEmpty {
            return try await translateWithAzureAPI(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )
        } else {
            return try await translateWithWebAPI(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )
        }
    }

    // Free Web API
    private func translateWithWebAPI(
        text: String,
        from: String,
        to: String
    ) async throws -> TranslationResult {
        // First get authentication token
        let tokenURL = URL(string: "https://edge.microsoft.com/translate/auth")!
        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (tokenData, tokenResponse) = try await session.data(for: tokenRequest)

        guard let tokenHttpResponse = tokenResponse as? HTTPURLResponse,
              tokenHttpResponse.statusCode == 200,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        let fromCode = convertToBingLanguageCode(from)
        let toCode = convertToBingLanguageCode(to)

        guard let translateURL = URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=\(fromCode)&to=\(toCode)") else {
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: translateURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let body = [["Text": text]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 429 {
            throw TranslationEngineError.rateLimitExceeded
        }

        guard httpResponse.statusCode == 200 else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        return try parseBingResponse(data, originalText: text)
    }

    // Azure official API
    private func translateWithAzureAPI(
        text: String,
        from: String,
        to: String
    ) async throws -> TranslationResult {
        let fromCode = convertToBingLanguageCode(from)
        let toCode = convertToBingLanguageCode(to)

        guard let url = URL(string: "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=\(fromCode)&to=\(toCode)") else {
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [["Text": text]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            throw TranslationEngineError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        return try parseBingResponse(data, originalText: text)
    }

    private func parseBingResponse(
        _ data: Data,
        originalText: String
    ) throws -> TranslationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first,
              let translations = first["translations"] as? [[String: Any]],
              let translation = translations.first,
              let translatedText = translation["text"] as? String else {
            throw TranslationEngineError.parseError
        }

        return TranslationResult(
            word: originalText,
            phonetic: nil,
            translation: translatedText,
            definitions: [],
            audioURL: nil
        )
    }

    func getAudioURL(for text: String, language: String) -> URL? {
        // Bing TTS requires separate API, not available for free
        return nil
    }

    private func convertToBingLanguageCode(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-Hans"
        case "zh-Hant": return "zh-Hant"
        default: return code
        }
    }
}
