//
//  SentenceTranslationService.swift
//  SnapTra Translator
//
//  Third-party sentence translation services.
//

import AppKit
import CryptoKit
import Foundation
import os.log
import WebKit

/// Service for translating sentences using third-party translation APIs.
final class SentenceTranslationService {
    private let session: URLSession
    private let logger = Logger(subsystem: "com.yelog.SnapTra-Translator", category: "SentenceTranslation")

    init(session: URLSession = SharedURLSession.ephemeral) {
        self.session = session
    }

    /// Translate text using the specified provider.
    func translate(
        text: String,
        provider: SentenceTranslationSource.SourceType,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String? {
        guard provider != .native else { return nil }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, sourceLanguage != targetLanguage else {
            return nil
        }

        do {
            switch provider {
            case .google:
                return try await translateGoogle(trimmedText, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            case .bing:
                return try await translateBing(trimmedText, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            case .youdao:
                return try await translateYoudao(trimmedText, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            case .native:
                return nil
            }
        } catch {
            logger.error("Sentence translation failed for \(provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Google Translate

    private func translateGoogle(
        _ text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String? {
        guard let target = googleLanguageCode(for: targetLanguage) else { return nil }

        var components = URLComponents(string: "https://translate.google.com/translate_a/single")
        components?.queryItems = [
            .init(name: "client", value: "gtx"),
            .init(name: "sl", value: googleLanguageCode(for: sourceLanguage) ?? "auto"),
            .init(name: "tl", value: target),
            .init(name: "dt", value: "t"),
            .init(name: "dj", value: "1"),
            .init(name: "ie", value: "UTF-8"),
            .init(name: "q", value: text),
        ]

        guard let url = components?.url else {
            throw SentenceTranslationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")

        let data = try await performRequest(request)
        let response = try JSONDecoder().decode(GoogleTranslateResponse.self, from: data)
        let translation = response.sentences.compactMap(\.trans).joined()

        guard !translation.isEmpty else { return nil }
        return translation
    }

    // MARK: - Youdao Translate

    private func translateYoudao(
        _ text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String? {
        guard let from = youdaoLanguageCode(for: sourceLanguage),
              let to = youdaoLanguageCode(for: targetLanguage) else {
            return nil
        }

        try await prewarmYoudaoSession()
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
            "i": text,
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
            throw SentenceTranslationError.invalidResponse
        }

        let decryptedData = try decryptYoudaoPayload(
            encryptedText,
            aesKeySeed: keyData.aesKey,
            aesIVSeed: keyData.aesIv
        )
        let response = try JSONDecoder().decode(YoudaoTranslationResponse.self, from: decryptedData)
        guard response.code == 0 else {
            throw SentenceTranslationError.providerRejected(
                provider: "Youdao",
                code: response.code,
                message: response.msg
            )
        }

        let translation = (response.translateResult ?? [])
            .flatMap { $0 }
            .compactMap(\.tgt)
            .joined()

        guard !translation.isEmpty else { return nil }
        return translation
    }

    private func prewarmYoudaoSession() async throws {
        var request = URLRequest(url: URL(string: "https://fanyi.youdao.com/")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://fanyi.youdao.com/", forHTTPHeaderField: "Referer")
        _ = try await performRequest(request)
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
            throw SentenceTranslationError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://fanyi.youdao.com/", forHTTPHeaderField: "Referer")

        let data = try await performRequest(request)
        let response = try JSONDecoder().decode(YoudaoKeyResponse.self, from: data)
        guard response.code == 0, let payload = response.data else {
            throw SentenceTranslationError.providerRejected(
                provider: "Youdao",
                code: response.code,
                message: response.msg
            )
        }
        return payload
    }

    // MARK: - Bing Translate

    private func translateBing(
        _ text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String? {
        guard let from = bingLanguageCode(for: sourceLanguage),
              let to = bingLanguageCode(for: targetLanguage) else {
            return nil
        }

        let tokenData = try await fetchBingTokenData()
        let body = percentEncodedForm([
            "text": text,
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
            throw SentenceTranslationError.invalidRequest
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
            throw SentenceTranslationError.captchaRequired
        }

        let translations = try JSONDecoder().decode([BingTranslationResponse].self, from: data)
            .flatMap(\.translations)
            .compactMap(\.text)
            .joined(separator: " ")

        guard !translations.isEmpty else { return nil }
        return translations
    }

    private func fetchBingTokenData() async throws -> BingTokenData {
        var request = URLRequest(url: URL(string: "https://www.bing.com/translator")!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SentenceTranslationError.invalidResponse
        }

        guard let ig = firstMatch(in: html, pattern: #"IG:\s*"([^"]+)""#, group: 1),
              let iid = firstMatch(in: html, pattern: #"data-iid\s*=\s*"([^"]+)""#, group: 1),
              let key = firstMatch(in: html, pattern: #"params_AbusePreventionHelper\s*=\s*\[(\d+),"[^"]+",\d+\]"#, group: 1),
              let token = firstMatch(in: html, pattern: #"params_AbusePreventionHelper\s*=\s*\[\d+,"([^"]+)",\d+\]"#, group: 1) else {
            throw SentenceTranslationError.invalidResponse
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

    // MARK: - Helpers

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SentenceTranslationError.invalidResponse
        }
        return data
    }

    private func decryptYoudaoPayload(
        _ payload: String,
        aesKeySeed: String,
        aesIVSeed: String
    ) throws -> Data {
        let paddedPayload = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let encrypted = Data(base64Encoded: paddedPayload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")) else {
            throw SentenceTranslationError.invalidResponse
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
            throw SentenceTranslationError.invalidResponse
        }

        output.removeSubrange(decryptedLength..<output.count)
        return output
    }

    private func md5Hex(_ input: String) -> String {
        md5Data(input).map { String(format: "%02x", $0) }.joined()
    }

    private func md5Data(_ input: String) -> Data {
        let source = Data(input.utf8)
        let digest = Insecure.MD5.hash(data: source)
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

    private func localeLanguageIdentifier(for identifier: String) -> String? {
        let locale = Locale(identifier: identifier)
        return locale.language.languageCode?.identifier
    }

    private func currentMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
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

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

// MARK: - Errors

enum SentenceTranslationError: Error {
    case invalidRequest
    case invalidResponse
    case captchaRequired
    case providerRejected(provider: String, code: Int, message: String?)
}

extension SentenceTranslationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid translation request."
        case .invalidResponse:
            return "The translation service returned an invalid response."
        case .captchaRequired:
            return "Bing translation requires a captcha."
        case .providerRejected(let provider, let code, let message):
            if let message, !message.isEmpty {
                return "\(provider) rejected the request (code \(code): \(message))."
            }
            return "\(provider) rejected the request (code \(code))."
        }
    }
}

// MARK: - Response Models

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
    let msg: String?
}

private struct YoudaoKeyData: Decodable {
    let secretKey: String
    let aesKey: String
    let aesIv: String
}

private struct YoudaoTranslationResponse: Decodable {
    let code: Int
    let msg: String?
    let translateResult: [[TranslationItem]]?

    struct TranslationItem: Decodable {
        let tgt: String?
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}


