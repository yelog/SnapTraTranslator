import AppKit
import Foundation
import os.log
import WebKit

final class OnlineDictionaryService {
    private let session: URLSession
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "OnlineDictionary")
    private let freeDictionaryService = FreeDictionaryService()

    init(session: URLSession = OnlineDictionaryService.makeSession()) {
        self.session = session
    }

    func lookup(
        _ word: String,
        provider: DictionarySource.SourceType,
        sourceLanguage: String,
        targetLanguage: String
    ) async -> DictionaryEntry? {
        guard provider.isOnline else { return nil }

        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty, sourceLanguage != targetLanguage else {
            return nil
        }

        do {
            switch provider {
            case .google:
                return try await lookupGoogle(trimmedWord, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            case .bing:
                return try await lookupBing(trimmedWord, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            case .youdao:
                return try await lookupYoudao(trimmedWord, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            case .deepl:
                return try await lookupDeepL(trimmedWord, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            case .freeDict:
                return await freeDictionaryService.lookup(trimmedWord)
            case .system, .ecdict:
                return nil
            }
        } catch {
            logger.error("Online dictionary lookup failed for \(provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func lookupGoogle(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> DictionaryEntry? {
        guard let target = googleLanguageCode(for: targetLanguage) else { return nil }

        var components = URLComponents(string: "https://translate.google.com/translate_a/single")
        components?.queryItems = [
            .init(name: "client", value: "gtx"),
            .init(name: "sl", value: googleLanguageCode(for: sourceLanguage) ?? "auto"),
            .init(name: "tl", value: target),
            .init(name: "dt", value: "t"),
            .init(name: "dj", value: "1"),
            .init(name: "ie", value: "UTF-8"),
            .init(name: "q", value: word),
        ]

        guard let url = components?.url else {
            throw OnlineDictionaryError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")

        let data = try await performRequest(request)
        let response = try JSONDecoder().decode(GoogleTranslateResponse.self, from: data)
        let translations = uniqueStrings(response.sentences.compactMap(\.trans))

        guard !translations.isEmpty else { return nil }
        return makeTranslationEntry(
            word: word,
            phonetic: nil,
            translations: translations,
            source: .googleTranslate
        )
    }

    private func lookupDeepL(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> DictionaryEntry? {
        guard let source = deepLPageLanguageCode(for: sourceLanguage),
              let target = deepLPageLanguageCode(for: targetLanguage) else {
            return nil
        }

        let translations = try await DeepLWebViewTranslator.lookup(
            word: word,
            sourceLanguage: source,
            targetLanguage: target,
            userAgent: Self.userAgent
        )

        guard !translations.isEmpty else { return nil }
        return makeTranslationEntry(
            word: word,
            phonetic: nil,
            translations: translations,
            source: .deepLTranslate
        )
    }

    private func lookupYoudao(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> DictionaryEntry? {
        guard let from = youdaoLanguageCode(for: sourceLanguage),
              let to = youdaoLanguageCode(for: targetLanguage) else {
            return nil
        }

        let keyData = try await fetchYoudaoKeyData()
        let mysticTime = currentMilliseconds()
        let sign = md5Hex("client=fanyideskweb&mysticTime=\(mysticTime)&product=webfanyi&key=\(keyData.secretKey)")
        let form = percentEncodedForm([
            "client": "fanyideskweb",
            "product": "webfanyi",
            "appVersion": "1.0.0",
            "vendor": "web",
            "pointParam": "client,mysticTime,product",
            "keyfrom": "fanyi.web",
            "i": word,
            "from": from,
            "to": to,
            "dictResult": "false",
            "keyid": "webfanyi",
            "sign": sign,
            "mysticTime": String(mysticTime),
        ])

        var request = URLRequest(url: URL(string: "https://dict.youdao.com/webtranslate")!)
        request.httpMethod = "POST"
        request.httpBody = form.data(using: .utf8)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://fanyi.youdao.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let encryptedData = try await performRequest(request)
        guard let encryptedText = String(data: encryptedData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !encryptedText.isEmpty else {
            throw OnlineDictionaryError.invalidResponse
        }

        let decryptedData = try decryptYoudaoPayload(
            encryptedText,
            aesKeySeed: keyData.aesKey,
            aesIVSeed: keyData.aesIv
        )
        let response = try JSONDecoder().decode(YoudaoTranslationResponse.self, from: decryptedData)
        let translations = uniqueStrings(
            response.translateResult
                .flatMap { $0 }
                .compactMap(\.tgt)
        )

        guard !translations.isEmpty else { return nil }
        return makeTranslationEntry(
            word: word,
            phonetic: nil,
            translations: translations,
            source: .youdaoDictionary
        )
    }

    private func lookupBing(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> DictionaryEntry? {
        if isBingDictionaryPagePair(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage),
           let entry = try await lookupBingDictionaryPage(word) {
            return entry
        }

        return try await lookupBingTranslatorAPI(
            word,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }

    private func lookupBingDictionaryPage(_ word: String) async throws -> DictionaryEntry? {
        var components = URLComponents(string: "https://cn.bing.com/dict/search")
        components?.queryItems = [.init(name: "q", value: word)]

        guard let url = components?.url else {
            throw OnlineDictionaryError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let data = try await performRequest(request)
        guard let html = String(data: data, encoding: .utf8),
              let description = metaContent(named: "description", in: html) else {
            return nil
        }

        let decoded = decodeHTML(description)
        let phonetic = bingPhonetic(from: decoded)
        let definitions = bingDefinitions(from: decoded)

        guard !definitions.isEmpty else { return nil }
        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            definitions: definitions,
            source: .bingDictionary,
            synonyms: [],
            isPretranslated: true
        )
    }

    private func lookupBingTranslatorAPI(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> DictionaryEntry? {
        guard let from = bingLanguageCode(for: sourceLanguage),
              let to = bingLanguageCode(for: targetLanguage) else {
            return nil
        }

        let tokenData = try await fetchBingTokenData()
        let body = percentEncodedForm([
            "text": word,
            "fromLang": from,
            "to": to,
            "token": tokenData.token,
            "key": tokenData.key,
            "tryFetchingGenderDebiasedTranslations": "true",
        ])

        var components = URLComponents(string: "https://\(tokenData.host)/ttranslatev3")
        components?.queryItems = [
            .init(name: "isVertical", value: "1"),
            .init(name: "IG", value: tokenData.ig),
            .init(name: "IID", value: tokenData.iid),
        ]

        guard let url = components?.url else {
            throw OnlineDictionaryError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://\(tokenData.host)/translator", forHTTPHeaderField: "Referer")
        if let cookie = tokenData.cookieHeader {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let data = try await performRequest(request)
        if let captcha = try? JSONDecoder().decode(BingCaptchaResponse.self, from: data),
           captcha.showCaptcha {
            return nil
        }

        let translations = try JSONDecoder().decode([BingTranslationResponse].self, from: data)
            .flatMap(\.translations)
            .compactMap(\.text)
        let uniqueTranslations = uniqueStrings(translations)

        guard !uniqueTranslations.isEmpty else { return nil }
        return makeTranslationEntry(
            word: word,
            phonetic: nil,
            translations: uniqueTranslations,
            source: .bingDictionary
        )
    }

    private func fetchBingTokenData() async throws -> BingTokenData {
        var request = URLRequest(url: URL(string: "https://www.bing.com/translator")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw OnlineDictionaryError.invalidResponse
        }

        guard let ig = firstMatch(in: html, pattern: #"IG:\s*"([^"]+)""#, group: 1),
              let iid = firstMatch(in: html, pattern: #"data-iid\s*=\s*"([^"]+)""#, group: 1),
              let key = firstMatch(in: html, pattern: #"params_AbusePreventionHelper\s*=\s*\[(\d+),"[^"]+",\d+\]"#, group: 1),
              let token = firstMatch(in: html, pattern: #"params_AbusePreventionHelper\s*=\s*\[\d+,"([^"]+)",\d+\]"#, group: 1) else {
            throw OnlineDictionaryError.invalidResponse
        }

        let cookieHeader = HTTPCookie.cookies(withResponseHeaderFields: httpResponse.allHeaderFields as? [String: String] ?? [:], for: request.url!)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        return BingTokenData(
            host: "www.bing.com",
            ig: ig,
            iid: iid,
            key: key,
            token: token,
            cookieHeader: cookieHeader.isEmpty ? nil : cookieHeader
        )
    }

    private func fetchYoudaoKeyData() async throws -> YoudaoKeyData {
        let mysticTime = currentMilliseconds()
        let sign = md5Hex("client=fanyideskweb&mysticTime=\(mysticTime)&product=webfanyi&key=asdjnjfenknafdfsdfsd")
        let query = percentEncodedForm([
            "client": "fanyideskweb",
            "product": "webfanyi",
            "appVersion": "1.0.0",
            "vendor": "web",
            "pointParam": "client,mysticTime,product",
            "keyfrom": "fanyi.web",
            "keyid": "webfanyi-key-getter",
            "sign": sign,
            "mysticTime": String(mysticTime),
        ])

        guard let url = URL(string: "https://dict.youdao.com/webtranslate/key?\(query)") else {
            throw OnlineDictionaryError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://fanyi.youdao.com/", forHTTPHeaderField: "Referer")

        let data = try await performRequest(request)
        let response = try JSONDecoder().decode(YoudaoKeyResponse.self, from: data)
        guard response.code == 0, let payload = response.data else {
            throw OnlineDictionaryError.invalidResponse
        }
        return payload
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw OnlineDictionaryError.invalidResponse
        }
        return data
    }

    private func makeTranslationEntry(
        word: String,
        phonetic: String?,
        translations: [String],
        source: DictionaryEntry.Source
    ) -> DictionaryEntry {
        DictionaryEntry(
            word: word,
            phonetic: phonetic,
            definitions: translations.map {
                DictionaryEntry.Definition(
                    partOfSpeech: "",
                    field: nil,
                    meaning: $0,
                    translation: $0,
                    examples: []
                )
            },
            source: source,
            synonyms: [],
            isPretranslated: true
        )
    }

    private func bingDefinitions(from description: String) -> [DictionaryEntry.Definition] {
        let tail = description.components(separatedBy: "释义，").last ?? description
        let tokens = tail
            .components(separatedBy: CharacterSet(charactersIn: "；;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var definitions: [DictionaryEntry.Definition] = []
        var currentPOS = ""

        for token in tokens {
            if token.hasPrefix("美[") || token.hasPrefix("英[") || token.hasPrefix("拼音[") {
                continue
            }

            if token.hasPrefix("网络释义：") {
                currentPOS = ""
                let translation = token.replacingOccurrences(of: "网络释义：", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translation.isEmpty else { continue }
                definitions.append(
                    DictionaryEntry.Definition(
                        partOfSpeech: currentPOS,
                        field: nil,
                        meaning: translation,
                        translation: translation,
                        examples: []
                    )
                )
                continue
            }

            if let match = regexGroups(
                in: token,
                pattern: #"^([A-Za-z][A-Za-z.&-]*\.)\s*(.+)$"#
            ), match.count == 3 {
                currentPOS = match[1]
                let translation = match[2].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translation.isEmpty else { continue }
                definitions.append(
                    DictionaryEntry.Definition(
                        partOfSpeech: currentPOS,
                        field: nil,
                        meaning: translation,
                        translation: translation,
                        examples: []
                    )
                )
                continue
            }

            definitions.append(
                DictionaryEntry.Definition(
                    partOfSpeech: currentPOS,
                    field: nil,
                    meaning: token,
                    translation: token,
                    examples: []
                )
            )
        }

        return deduplicatedDefinitions(definitions)
    }

    private func bingPhonetic(from description: String) -> String? {
        let patterns = [
            #"美\[([^\]]+)\]"#,
            #"英\[([^\]]+)\]"#,
            #"拼音\[([^\]]+)\]"#,
        ]

        var parts: [String] = []
        for pattern in patterns {
            guard let value = firstMatch(in: description, pattern: pattern, group: 1) else {
                continue
            }
            if pattern.contains("拼音") {
                parts.append("[\(value)]")
            } else if pattern.contains("美") {
                parts.append("US [\(value)]")
            } else {
                parts.append("UK [\(value)]")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }

    private func metaContent(named name: String, in html: String) -> String? {
        firstMatch(
            in: html,
            pattern: #"<meta[^>]+name=\""# + NSRegularExpression.escapedPattern(for: name) + #"\"[^>]+content=\"([^\"]+)""#,
            group: 1
        )
    }

    private func decodeHTML(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let decoded = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ).string else {
            return text
        }

        return decoded
    }

    private func decryptYoudaoPayload(
        _ payload: String,
        aesKeySeed: String,
        aesIVSeed: String
    ) throws -> Data {
        let paddedPayload = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let encrypted = Data(base64Encoded: paddedPayload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")) else {
            throw OnlineDictionaryError.invalidResponse
        }

        let key = md5Data(aesKeySeed)
        let iv = md5Data(aesIVSeed)
        return try aes128CBCDecrypt(encrypted, key: key, iv: iv)
    }

    private func aes128CBCDecrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        let outputLength = data.count + kCCBlockSizeAES128
        var output = Data(count: outputLength)
        var decryptedLength: size_t = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputLength,
                            &decryptedLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw OnlineDictionaryError.invalidResponse
        }

        output.removeSubrange(decryptedLength..<output.count)
        return output
    }

    private func md5Hex(_ input: String) -> String {
        md5Data(input).map { String(format: "%02x", $0) }.joined()
    }

    private func md5Data(_ input: String) -> Data {
        let source = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        source.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(source.count), &digest)
        }
        return Data(digest)
    }

    private func percentEncodedForm(_ parameters: [String: String]) -> String {
        parameters
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .sorted()
            .joined(separator: "&")
    }

    private func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }

    private func googleLanguageCode(for language: String) -> String? {
        switch language {
        case "zh", "zh-Hans":
            return "zh-CN"
        case "zh-Hant":
            return "zh-TW"
        default:
            return localeLanguageIdentifier(for: language)
        }
    }

    private func youdaoLanguageCode(for language: String) -> String? {
        switch language {
        case "zh", "zh-Hans":
            return "zh-CHS"
        case "zh-Hant":
            return "zh-CHT"
        default:
            return localeLanguageIdentifier(for: language)?.lowercased()
        }
    }

    private func bingLanguageCode(for language: String) -> String? {
        switch language {
        case "zh", "zh-Hans":
            return "zh-Hans"
        case "zh-Hant":
            return "zh-Hant"
        default:
            return localeLanguageIdentifier(for: language)
        }
    }

    private func deepLPageLanguageCode(for language: String) -> String? {
        switch language {
        case "auto", "und":
            return "auto"
        case "zh":
            return "zh"
        case "zh-Hans":
            return "zh-Hans"
        case "zh-Hant":
            return "zh-Hant"
        case "pt-BR":
            return "pt-BR"
        case "pt-PT", "pt":
            return "pt-PT"
        default:
            return localeLanguageIdentifier(for: language)
        }
    }

    private func deepLLanguageCode(for language: String) -> String? {
        switch language {
        case "zh", "zh-Hans", "zh-Hant":
            return "ZH"
        case "pt":
            return "PT-BR"
        default:
            return localeLanguageIdentifier(for: language)?.uppercased()
        }
    }

    private func deepLRegionalVariant(for language: String) -> String? {
        switch language {
        case "zh-Hant":
            return "zh-Hant"
        case "zh", "zh-Hans":
            return "zh-Hans"
        default:
            return nil
        }
    }

    private func localeLanguageIdentifier(for identifier: String) -> String? {
        let locale = Locale(identifier: identifier)
        return locale.language.languageCode?.identifier
    }

    private func isBingDictionaryPagePair(sourceLanguage: String, targetLanguage: String) -> Bool {
        let pair = Set([
            localeLanguageIdentifier(for: sourceLanguage) ?? sourceLanguage,
            localeLanguageIdentifier(for: targetLanguage) ?? targetLanguage,
        ])
        return pair == Set(["en", "zh"])
    }

    private func deepLTimestamp(for text: String) -> Int {
        let now = currentMilliseconds()
        let count = text.filter { $0 == "i" }.count
        guard count > 0 else { return now }
        let rounded = count + 1
        return now - (now % rounded) + rounded
    }

    private func currentMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func deduplicatedDefinitions(
        _ definitions: [DictionaryEntry.Definition]
    ) -> [DictionaryEntry.Definition] {
        var seen = Set<String>()
        return definitions.compactMap { definition in
            let translation = definition.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !translation.isEmpty else { return nil }

            let key = "\(definition.partOfSpeech.lowercased())|\(translation.lowercased())"
            guard seen.insert(key).inserted else { return nil }
            return definition
        }
    }

    private func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        regexGroups(in: text, pattern: pattern)?[safe: group]
    }

    private func regexGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

private enum OnlineDictionaryError: Error {
    case invalidRequest
    case invalidResponse
}

private struct GoogleTranslateResponse: Decodable {
    let sentences: [Sentence]

    struct Sentence: Decodable {
        let trans: String?
    }
}

private struct BingTokenData {
    let host: String
    let ig: String
    let iid: String
    let key: String
    let token: String
    let cookieHeader: String?
}

private struct BingCaptchaResponse: Decodable {
    let showCaptcha: Bool

    enum CodingKeys: String, CodingKey {
        case showCaptcha = "ShowCaptcha"
    }
}

private struct BingTranslationResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let text: String?
    }
}

private struct YoudaoKeyResponse: Decodable {
    let data: YoudaoKeyData?
    let code: Int
}

private struct YoudaoKeyData: Decodable {
    let secretKey: String
    let aesKey: String
    let aesIv: String
}

private struct YoudaoTranslationResponse: Decodable {
    let translateResult: [[TranslationItem]]

    struct TranslationItem: Decodable {
        let tgt: String?
    }
}

private struct DeepLRequest: Encodable {
    let jsonrpc: String
    let method: String
    let id: Int
    let params: Params

    struct Params: Encodable {
        let texts: [Text]
        let splitting: String
        let lang: Language
        let timestamp: Int
        let commonJobParams: CommonJobParams

        enum CodingKeys: String, CodingKey {
            case texts
            case splitting
            case lang
            case timestamp
            case commonJobParams
        }
    }

    struct Text: Encodable {
        let text: String
        let requestAlternatives: Int
    }

    struct Language: Encodable {
        let sourceLangUserSelected: String
        let targetLang: String

        enum CodingKeys: String, CodingKey {
            case sourceLangUserSelected = "source_lang_user_selected"
            case targetLang = "target_lang"
        }
    }

    struct CommonJobParams: Encodable {
        let regionalVariant: String?
        let mode: String
        let browserType: Int
        let textType: String

        enum CodingKeys: String, CodingKey {
            case regionalVariant
            case mode
            case browserType
            case textType
        }
    }
}

private struct DeepLResponse: Decodable {
    let result: ResultPayload?

    struct ResultPayload: Decodable {
        let texts: [TextPayload]
    }

    struct TextPayload: Decodable {
        let text: String
        let alternatives: [Alternative]?
    }

    struct Alternative: Decodable {
        let text: String
    }
}

@MainActor
private final class DeepLWebViewTranslator: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let sourceLanguage: String
    private let targetLanguage: String
    private let word: String
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    private init(
        word: String,
        sourceLanguage: String,
        targetLanguage: String,
        userAgent: String
    ) {
        self.word = word
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent

        super.init()
        webView.navigationDelegate = self
    }

    static func lookup(
        word: String,
        sourceLanguage: String,
        targetLanguage: String,
        userAgent: String
    ) async throws -> [String] {
        let translator = DeepLWebViewTranslator(
            word: word,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            userAgent: userAgent
        )
        return try await translator.performLookup()
    }

    private func performLookup() async throws -> [String] {
        guard let url = makeTranslationURL() else {
            throw OnlineDictionaryError.invalidRequest
        }

        webView.load(URLRequest(url: url))
        try await waitForNavigation()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await injectSourceText()

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            let state = try await readPageState()
            if state.source == word, !state.target.isEmpty {
                return [state.target]
            }
            try await Task.sleep(nanoseconds: 350_000_000)
        }

        return []
    }

    private func makeTranslationURL() -> URL? {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        return URL(
            string: "https://www.deepl.com/en/translator#\(sourceLanguage)/\(targetLanguage)/\(encodedWord)"
        )
    }

    private func waitForNavigation() async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    private func injectSourceText() async throws {
        let script = """
        (() => {
          const textboxes = Array.from(document.querySelectorAll('[role="textbox"][data-content="true"]'));
          const source = textboxes.find((element) => {
            const label = element.getAttribute('aria-labelledby') || '';
            return label.includes('source');
          }) || textboxes.find((element) => element.getAttribute('contenteditable') === 'true');

          if (!source) {
            return JSON.stringify({ ok: false, reason: 'missing-source' });
          }

          const text = \(javaScriptLiteral(word));
          source.focus();
          source.textContent = text;

          source.dispatchEvent(new InputEvent('beforeinput', {
            bubbles: true,
            cancelable: true,
            inputType: 'insertText',
            data: text
          }));
          source.dispatchEvent(new InputEvent('input', {
            bubbles: true,
            inputType: 'insertText',
            data: text
          }));
          source.dispatchEvent(new Event('change', { bubbles: true }));

          return JSON.stringify({
            ok: true,
            text: (source.innerText || source.textContent || '').trim()
          });
        })();
        """

        guard let payload = try await webView.evaluateJavaScript(script) as? String,
              let data = payload.data(using: .utf8) else {
            throw OnlineDictionaryError.invalidResponse
        }

        let result = try JSONDecoder().decode(DeepLInjectionResult.self, from: data)
        guard result.ok else {
            throw OnlineDictionaryError.invalidResponse
        }
    }

    private func readPageState() async throws -> DeepLPageState {
        let script = """
        (() => {
          const textboxes = Array.from(document.querySelectorAll('[role="textbox"][data-content="true"]'));
          const source = textboxes.find((element) => {
            const label = element.getAttribute('aria-labelledby') || '';
            return label.includes('source');
          }) || textboxes.find((element) => element.getAttribute('contenteditable') === 'true');
          const target = textboxes.find((element) => {
            const label = element.getAttribute('aria-labelledby') || '';
            return label.includes('target');
          }) || textboxes.find((element) => element !== source);

          const normalize = (element) => {
            if (!element) { return ''; }
            return (element.innerText || element.textContent || element.value || '')
              .replace(/\\u00a0/g, ' ')
              .trim();
          };

          return JSON.stringify({
            source: normalize(source),
            target: normalize(target)
          });
        })();
        """

        guard let payload = try await webView.evaluateJavaScript(script) as? String,
              let data = payload.data(using: .utf8) else {
            throw OnlineDictionaryError.invalidResponse
        }

        return try JSONDecoder().decode(DeepLPageState.self, from: data)
    }

    private func javaScriptLiteral(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return String(data: data ?? Data("null".utf8), encoding: .utf8) ?? "null"
    }
}

private struct DeepLPageState: Decodable {
    let source: String
    let target: String
}

private struct DeepLInjectionResult: Decodable {
    let ok: Bool
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
