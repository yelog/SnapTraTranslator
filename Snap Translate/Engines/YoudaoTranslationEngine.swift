import CryptoKit
import Foundation

final class YoudaoTranslationEngine: TranslationEngine {
    let engineType: TranslationEngineType = .youdao
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
        if config.useCustomAPI && !config.apiKey.isEmpty && !config.secretKey.isEmpty {
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

    // Free API (Youdao Dictionary Web)
    private func translateWithFreeAPI(
        text: String,
        from: String,
        to: String
    ) async throws -> TranslationResult {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        let urlString = "https://dict.youdao.com/jsonapi_s?doctype=json&jsonversion=4&q=\(encodedText)"

        guard let url = URL(string: urlString) else {
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        return try parseYoudaoFreeResponse(data, originalText: text)
    }

    // Official API
    private func translateWithOfficialAPI(
        text: String,
        from: String,
        to: String
    ) async throws -> TranslationResult {
        let curtime = String(Int(Date().timeIntervalSince1970))
        let salt = UUID().uuidString
        let signStr = "\(config.apiKey)\(truncate(text))\(salt)\(curtime)\(config.secretKey)"
        let sign = sha256(signStr)

        let fromCode = convertToYoudaoLanguageCode(from)
        let toCode = convertToYoudaoLanguageCode(to)

        var components = URLComponents(string: "https://openapi.youdao.com/api")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: fromCode),
            URLQueryItem(name: "to", value: toCode),
            URLQueryItem(name: "appKey", value: config.apiKey),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "signType", value: "v3"),
            URLQueryItem(name: "curtime", value: curtime)
        ]

        guard let url = components.url else {
            throw TranslationEngineError.networkError(URLError(.badURL))
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TranslationEngineError.networkError(URLError(.badServerResponse))
        }

        return try parseYoudaoOfficialResponse(data, originalText: text)
    }

    private func parseYoudaoFreeResponse(
        _ data: Data,
        originalText: String
    ) throws -> TranslationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationEngineError.parseError
        }

        var phonetic: String?
        var translation = ""
        var definitions: [DictionaryEntry.Definition] = []

        // Extract from ec (English-Chinese dictionary)
        if let ec = json["ec"] as? [String: Any],
           let wordList = ec["word"] as? [[String: Any]],
           let firstWord = wordList.first {
            // Extract phonetic
            if let ukphone = firstWord["ukphone"] as? String, !ukphone.isEmpty {
                phonetic = "/\(ukphone)/"
            } else if let usphone = firstWord["usphone"] as? String, !usphone.isEmpty {
                phonetic = "/\(usphone)/"
            }

            // Extract definitions with part of speech
            if let trs = firstWord["trs"] as? [[String: Any]] {
                for tr in trs.prefix(5) {
                    let pos = (tr["pos"] as? String) ?? ""
                    if let tran = tr["tran"] as? String {
                        definitions.append(DictionaryEntry.Definition(
                            partOfSpeech: pos,
                            meaning: tran,
                            translation: nil,
                            examples: []
                        ))
                    }
                }
            }
        }

        // Get main translation from fanyi
        if let fanyi = json["fanyi"] as? [String: Any],
           let tran = fanyi["tran"] as? String {
            translation = tran
        } else if !definitions.isEmpty, let first = definitions.first {
            translation = first.meaning
        }

        // Fallback to simple translation
        if translation.isEmpty {
            if let simple = json["simple"] as? [String: Any],
               let wordList = simple["word"] as? [[String: Any]],
               let firstWord = wordList.first,
               let ust = firstWord["ust"] as? String {
                translation = ust
            }
        }

        // Another fallback
        if translation.isEmpty {
            if let web = json["web"] as? [String: Any],
               let translations = web["trans"] as? [[String: Any]],
               let first = translations.first,
               let summary = first["summary"] as? String {
                translation = summary
            }
        }

        if translation.isEmpty {
            throw TranslationEngineError.emptyResponse
        }

        return TranslationResult(
            word: originalText,
            phonetic: phonetic,
            translation: translation,
            definitions: definitions,
            audioURL: getAudioURL(for: originalText, language: "en")
        )
    }

    private func parseYoudaoOfficialResponse(
        _ data: Data,
        originalText: String
    ) throws -> TranslationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorCode = json["errorCode"] as? String else {
            throw TranslationEngineError.parseError
        }

        if errorCode != "0" {
            if errorCode == "108" {
                throw TranslationEngineError.invalidAPIKey
            }
            throw TranslationEngineError.parseError
        }

        guard let translations = json["translation"] as? [String],
              let translation = translations.first else {
            throw TranslationEngineError.emptyResponse
        }

        var phonetic: String?
        var definitions: [DictionaryEntry.Definition] = []

        if let basic = json["basic"] as? [String: Any] {
            if let ukPhonetic = basic["uk-phonetic"] as? String, !ukPhonetic.isEmpty {
                phonetic = "/\(ukPhonetic)/"
            } else if let usPhonetic = basic["us-phonetic"] as? String, !usPhonetic.isEmpty {
                phonetic = "/\(usPhonetic)/"
            }

            if let explains = basic["explains"] as? [String] {
                for explain in explains.prefix(3) {
                    // Parse format like "n. 苹果；苹果树"
                    let parts = explain.components(separatedBy: ". ")
                    if parts.count >= 2 {
                        definitions.append(DictionaryEntry.Definition(
                            partOfSpeech: parts[0] + ".",
                            meaning: parts.dropFirst().joined(separator: ". "),
                            translation: nil,
                            examples: []
                        ))
                    } else {
                        definitions.append(DictionaryEntry.Definition(
                            partOfSpeech: "",
                            meaning: explain,
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
            translation: translation,
            definitions: definitions,
            audioURL: getAudioURL(for: originalText, language: "en")
        )
    }

    private func truncate(_ text: String) -> String {
        if text.count <= 20 {
            return text
        }
        let start = String(text.prefix(10))
        let end = String(text.suffix(10))
        return "\(start)\(text.count)\(end)"
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func convertToYoudaoLanguageCode(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CHS"
        case "zh-Hant": return "zh-CHT"
        default: return code
        }
    }

    func getAudioURL(for text: String, language: String) -> URL? {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        // type=1 is UK pronunciation, type=2 is US pronunciation
        return URL(string: "https://dict.youdao.com/dictvoice?audio=\(encodedText)&type=2")
    }
}
