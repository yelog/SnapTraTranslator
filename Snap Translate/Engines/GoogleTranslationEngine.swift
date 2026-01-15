import Foundation

final class GoogleTranslationEngine: TranslationEngine {
    let engineType: TranslationEngineType = .google
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
            return try await translateWithOfficialAPI(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )
        } else {
            return try await translateWithFreeAPI(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )
        }
    }

    // Free API (translate.googleapis.com)
    private func translateWithFreeAPI(
        text: String,
        from: String,
        to: String
    ) async throws -> TranslationResult {
        let fromCode = convertToGoogleLanguageCode(from)
        let toCode = convertToGoogleLanguageCode(to)

        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("❌ Google: Failed to encode text")
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        let urlString = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(fromCode)&tl=\(toCode)&dt=t&dt=bd&dt=rm&q=\(encodedText)"
        print("🌐 Google API URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("❌ Google: Invalid URL")
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        print("📡 Google: Sending request...")
        let (data, response) = try await session.data(for: request)
        print("📥 Google: Received response, data size: \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Google: Invalid HTTP response")
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        print("📊 Google: Status code: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 429 {
            print("❌ Google: Rate limit exceeded")
            throw TranslationEngineError.rateLimitExceeded
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ Google: HTTP error \(httpResponse.statusCode)")
            // Print response body for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response body: \(responseString.prefix(500))")
            }
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        print("✅ Google: Parsing response...")
        return try parseGoogleFreeResponse(data, originalText: text, sourceLanguage: from)
    }

    // Official API (needs API Key)
    private func translateWithOfficialAPI(
        text: String,
        from: String,
        to: String
    ) async throws -> TranslationResult {
        let fromCode = convertToGoogleLanguageCode(from)
        let toCode = convertToGoogleLanguageCode(to)

        guard let url = URL(string: "https://translation.googleapis.com/language/translate/v2") else {
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "q": text,
            "source": fromCode,
            "target": toCode,
            "key": config.apiKey
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 403 {
            throw TranslationEngineError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        return try parseGoogleOfficialResponse(data, originalText: text)
    }

    private func parseGoogleFreeResponse(
        _ data: Data,
        originalText: String,
        sourceLanguage: String
    ) throws -> TranslationResult {
        print("🔧 Google: Parsing JSON response...")

        // Debug: print raw response
        if let rawString = String(data: data, encoding: .utf8) {
            print("📄 Raw response preview: \(rawString.prefix(300))...")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            print("❌ Google: Failed to parse JSON as array")
            throw TranslationEngineError.parseError
        }

        print("✅ Google: JSON parsed, array count: \(json.count)")

        // Extract translation
        var translatedText = ""
        if let translations = json.first as? [[Any]] {
            print("📝 Google: Found \(translations.count) translation segments")
            for item in translations {
                if let text = item.first as? String {
                    translatedText += text
                }
            }
        } else {
            print("❌ Google: First element is not an array of arrays")
        }

        print("📝 Google: Extracted translation: '\(translatedText)'")

        if translatedText.isEmpty {
            print("❌ Google: Translation is empty")
            throw TranslationEngineError.emptyResponse
        }

        // Extract phonetic (if available)
        var phonetic: String?
        if json.count > 3, let phoneticData = json[3] as? String, !phoneticData.isEmpty {
            phonetic = "/\(phoneticData)/"
        }

        // Extract definitions (dt=bd parameter)
        var definitions: [DictionaryEntry.Definition] = []
        if json.count > 1, let dictData = json[1] as? [[Any]] {
            for item in dictData {
                if item.count >= 2,
                   let pos = item[0] as? String,
                   let meanings = item[1] as? [String] {
                    for meaning in meanings.prefix(2) {
                        definitions.append(DictionaryEntry.Definition(
                            partOfSpeech: pos,
                            meaning: meaning,
                            translation: nil,
                            examples: []
                        ))
                    }
                }
            }
        }

        return TranslationResult(
            word: originalText,
            phonetic: phonetic,
            translation: translatedText,
            definitions: definitions,
            audioURL: getAudioURL(for: originalText, language: sourceLanguage)
        )
    }

    private func parseGoogleOfficialResponse(
        _ data: Data,
        originalText: String
    ) throws -> TranslationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let translations = dataDict["translations"] as? [[String: Any]],
              let first = translations.first,
              let translatedText = first["translatedText"] as? String else {
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
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let langCode = convertToGoogleLanguageCode(language)
        return URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=\(langCode)&q=\(encodedText)")
    }

    private func convertToGoogleLanguageCode(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return code
        }
    }
}
