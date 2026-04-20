import Foundation

final class OnlineDictionaryService {
    private let session: URLSession

    init(session: URLSession = SharedURLSession.ephemeral) {
        self.session = session
    }

    func lookup(
        _ word: String,
        source: DictionarySource.SourceType,
        sourceLanguage: String,
        targetLanguage: String
    ) async -> DictionaryEntry? {
        switch source {
        case .youdao:
            guard Self.isEnglishLanguage(sourceLanguage), Self.isChineseLanguage(targetLanguage) else {
                return nil
            }
            return await lookupYoudao(word)
        case .google:
            guard Self.isEnglishLanguage(sourceLanguage) else {
                return nil
            }
            return await lookupGoogle(word, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        case .freeDictionaryAPI:
            guard Self.isEnglishLanguage(sourceLanguage) else {
                return nil
            }
            return await lookupFreeDictionary(word)
        case .ecdict, .system:
            return nil
        }
    }

    private func lookupYoudao(_ word: String) async -> DictionaryEntry? {
        var components = URLComponents(string: "https://m.youdao.com/dict")
        components?.queryItems = [
            .init(name: "le", value: "eng"),
            .init(name: "q", value: word),
        ]

        guard let url = components?.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://m.youdao.com/", forHTTPHeaderField: "Referer")

        do {
            let data = try await performRequest(request)
            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return Self.parseYoudaoHTML(html, word: word)
        } catch {
            return nil
        }
    }

    private func lookupGoogle(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async -> DictionaryEntry? {
        guard let target = Self.googleLanguageCode(for: targetLanguage) else {
            return nil
        }

        var components = URLComponents(string: "https://translate.google.com/translate_a/single")
        components?.queryItems = [
            .init(name: "client", value: "gtx"),
            .init(name: "sl", value: Self.googleLanguageCode(for: sourceLanguage) ?? "auto"),
            .init(name: "tl", value: target),
            .init(name: "dt", value: "t"),
            .init(name: "dt", value: "bd"),
            .init(name: "dt", value: "md"),
            .init(name: "dt", value: "ex"),
            .init(name: "dj", value: "1"),
            .init(name: "ie", value: "UTF-8"),
            .init(name: "q", value: word),
        ]

        guard let url = components?.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")

        do {
            let data = try await performRequest(request)
            return Self.parseGoogleResponse(data, word: word)
        } catch {
            return nil
        }
    }

    private func lookupFreeDictionary(_ word: String) async -> DictionaryEntry? {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encodedWord)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let data = try await performRequest(request)
            return Self.parseFreeDictionaryResponse(data, word: word)
        } catch {
            return nil
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              !data.isEmpty else {
            throw OnlineDictionaryError.invalidResponse
        }
        return data
    }

    nonisolated static func parseGoogleResponse(_ data: Data, word: String) -> DictionaryEntry? {
        guard let response = try? JSONDecoder().decode(GoogleDictionaryResponse.self, from: data) else {
            return nil
        }

        var translationsByPOS: [String: String] = [:]
        for section in response.dict ?? [] {
            let terms = (section.terms ?? [])
                .map(Self.collapseWhitespace)
                .filter { !$0.isEmpty }
            guard !terms.isEmpty else { continue }
            translationsByPOS[Self.normalizedPartOfSpeech(section.pos)] = terms.joined(separator: "；")
        }

        var examplesByDefinitionID: [String: [String]] = [:]
        for example in response.examples?.example ?? [] {
            let text = Self.collapseWhitespace(Self.stripHTML(example.text))
            guard let definitionID = example.definitionID, !text.isEmpty else { continue }
            examplesByDefinitionID[definitionID, default: []].append(text)
        }

        var definitions: [DictionaryEntry.Definition] = []
        for section in response.definitions ?? [] {
            let partOfSpeech = Self.normalizedPartOfSpeech(section.pos)
            let translation = translationsByPOS[partOfSpeech]
            for entry in section.entry {
                let gloss = Self.collapseWhitespace(Self.stripHTML(entry.gloss))
                guard !gloss.isEmpty else { continue }
                let examples = examplesByDefinitionID[entry.definitionID ?? ""] ?? []
                definitions.append(
                    DictionaryEntry.Definition(
                        partOfSpeech: partOfSpeech,
                        field: nil,
                        meaning: gloss,
                        translation: translation,
                        examples: Array(examples.prefix(3))
                    )
                )
            }
        }

        if definitions.isEmpty {
            for section in response.dict ?? [] {
                let translation = (section.terms ?? [])
                    .map(Self.collapseWhitespace)
                    .filter { !$0.isEmpty }
                    .joined(separator: "；")
                guard !translation.isEmpty else { continue }
                definitions.append(
                    DictionaryEntry.Definition(
                        partOfSpeech: Self.normalizedPartOfSpeech(section.pos),
                        field: nil,
                        meaning: translation,
                        translation: translation,
                        examples: []
                    )
                )
            }
        }

        if definitions.isEmpty,
           let translation = response.sentences?.compactMap(\.trans).first,
           !translation.isEmpty {
            definitions = [
                DictionaryEntry.Definition(
                    partOfSpeech: "",
                    field: nil,
                    meaning: translation,
                    translation: translation,
                    examples: []
                ),
            ]
        }

        guard !definitions.isEmpty else {
            return nil
        }

        return DictionaryEntry(
            word: word,
            phonetic: nil,
            definitions: definitions,
            source: .googleTranslate,
            synonyms: [],
            isPretranslated: true
        )
    }

    nonisolated static func parseFreeDictionaryResponse(_ data: Data, word: String) -> DictionaryEntry? {
        guard let response = try? JSONDecoder().decode([FreeDictionaryEntryResponse].self, from: data),
              let first = response.first else {
            return nil
        }

        let phonetic = first.phonetics?
            .compactMap { phonetic in
                let text = phonetic.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.isEmpty ? nil : text
            }
            .first

        var definitions: [DictionaryEntry.Definition] = []
        var synonyms: [String] = []

        for meaning in first.meanings ?? [] {
            synonyms.append(contentsOf: meaning.synonyms ?? [])
            for item in meaning.definitions ?? [] {
                synonyms.append(contentsOf: item.synonyms ?? [])
                let meaningText = Self.collapseWhitespace(item.definition)
                guard !meaningText.isEmpty else { continue }
                let example = item.example.map(Self.collapseWhitespace)
                definitions.append(
                    DictionaryEntry.Definition(
                        partOfSpeech: Self.normalizedPartOfSpeech(meaning.partOfSpeech),
                        field: nil,
                        meaning: meaningText,
                        translation: nil,
                        examples: example.map { [$0] } ?? []
                    )
                )
            }
        }

        guard !definitions.isEmpty else {
            return nil
        }

        return DictionaryEntry(
            word: first.word ?? word,
            phonetic: phonetic,
            definitions: definitions,
            source: .freeDictionaryAPI,
            synonyms: Self.uniqueStrings(synonyms),
            isPretranslated: false
        )
    }

    nonisolated static func parseYoudaoHTML(_ html: String, word: String) -> DictionaryEntry? {
        let ukPhonetic = firstMatch(
            in: html,
            pattern: #"(?s)英\s*<span class="phonetic">\s*([^<]+)\s*</span>"#
        )
        let usPhonetic = firstMatch(
            in: html,
            pattern: #"(?s)美\s*<span class="phonetic">\s*([^<]+)\s*</span>"#
        )
        let phonetic = joinedPhonetic(uk: ukPhonetic, us: usPhonetic)

        guard let basicSection = firstMatch(
            in: html,
            pattern: #"(?s)<div id="ec" class="trans-container ec ">\s*.*?<ul>(.*?)</ul>"#
        ) else {
            return nil
        }

        let items = allMatches(in: basicSection, pattern: #"(?s)<li>(.*?)</li>"#)
        let definitions = items.compactMap { itemHTML -> DictionaryEntry.Definition? in
            let text = collapseWhitespace(stripHTML(itemHTML))
            guard !text.isEmpty else { return nil }
            let (partOfSpeech, translation) = splitYoudaoDefinitionText(text)
            return DictionaryEntry.Definition(
                partOfSpeech: partOfSpeech,
                field: nil,
                meaning: translation,
                translation: translation,
                examples: []
            )
        }

        guard !definitions.isEmpty else {
            return nil
        }

        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            definitions: definitions,
            source: .youdaoDictionary,
            synonyms: [],
            isPretranslated: true
        )
    }

    nonisolated private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"

    nonisolated private static func joinedPhonetic(uk: String?, us: String?) -> String? {
        var parts: [String] = []
        if let uk = uk?.trimmingCharacters(in: .whitespacesAndNewlines), !uk.isEmpty {
            parts.append("英 \(uk)")
        }
        if let us = us?.trimmingCharacters(in: .whitespacesAndNewlines), !us.isEmpty {
            parts.append("美 \(us)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    nonisolated private static func splitYoudaoDefinitionText(_ text: String) -> (String, String) {
        if let match = firstMatchGroups(
            in: text,
            pattern: #"^([A-Za-z]+(?:\.)?)\s*(.+)$"#
        ), match.count == 2 {
            let partOfSpeech = normalizedPartOfSpeech(match[0].replacingOccurrences(of: ".", with: ""))
            let translation = collapseWhitespace(match[1])
            return (partOfSpeech, translation)
        }

        if let match = firstMatchGroups(
            in: text,
            pattern: #"^【([^】]+)】\s*(.+)$"#
        ), match.count == 2 {
            let partOfSpeech = normalizedYoudaoPartOfSpeech(match[0])
            let translation = collapseWhitespace(match[1])
            return (partOfSpeech, translation)
        }

        return ("", text)
    }

    nonisolated private static func normalizedYoudaoPartOfSpeech(_ value: String) -> String {
        let label = collapseWhitespace(value)
        switch label {
        case "名", "名词":
            return "n"
        case "动", "动词":
            return "v"
        case "形", "形容词":
            return "adj"
        case "副", "副词":
            return "adv"
        case "介", "介词":
            return "prep"
        case "连", "连词":
            return "conj"
        case "代", "代词":
            return "pron"
        case "叹", "叹词":
            return "interj"
        default:
            return label
        }
    }

    nonisolated private static func isEnglishLanguage(_ identifier: String) -> Bool {
        identifier.hasPrefix("en")
    }

    nonisolated private static func isChineseLanguage(_ identifier: String) -> Bool {
        identifier.hasPrefix("zh")
    }

    nonisolated private static func googleLanguageCode(for identifier: String) -> String? {
        if identifier.hasPrefix("zh-Hans") || identifier == "zh" {
            return "zh-CN"
        }
        if identifier.hasPrefix("zh-Hant") {
            return "zh-TW"
        }

        switch Locale(identifier: identifier).language.languageCode?.identifier ?? identifier {
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "de": return "de"
        case "es": return "es"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ar"
        case "th": return "th"
        case "vi": return "vi"
        default: return nil
        }
    }

    nonisolated private static func normalizedPartOfSpeech(_ value: String) -> String {
        collapseWhitespace(value).lowercased()
    }

    nonisolated private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&lt;": "<",
            "&gt;": ">",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return collapseWhitespace(text)
    }

    nonisolated private static func collapseWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []
        for value in values.map(collapseWhitespace) where !value.isEmpty {
            if seen.insert(value).inserted {
                results.append(value)
            }
        }
        return results
    }

    nonisolated private static func firstMatch(in text: String, pattern: String) -> String? {
        firstMatchGroups(in: text, pattern: pattern)?.first
    }

    nonisolated private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capturedRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[capturedRange])
        }
    }

    nonisolated private static func firstMatchGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let capturedRange = Range(match.range(at: index), in: text) else {
                return nil
            }
            return String(text[capturedRange])
        }
    }
}

private enum OnlineDictionaryError: Error {
    case invalidResponse
}

private struct GoogleDictionaryResponse: Decodable {
    let sentences: [GoogleSentence]?
    let dict: [GoogleDictionarySection]?
    let definitions: [GoogleDefinitionSection]?
    let examples: GoogleExamplesSection?
}

private struct GoogleSentence: Decodable {
    let trans: String?
}

private struct GoogleDictionarySection: Decodable {
    let pos: String
    let terms: [String]?
}

private struct GoogleDefinitionSection: Decodable {
    let pos: String
    let entry: [GoogleDefinitionEntry]
}

private struct GoogleDefinitionEntry: Decodable {
    let gloss: String
    let definitionID: String?

    enum CodingKeys: String, CodingKey {
        case gloss
        case definitionID = "definition_id"
    }
}

private struct GoogleExamplesSection: Decodable {
    let example: [GoogleExampleEntry]?
}

private struct GoogleExampleEntry: Decodable {
    let text: String
    let definitionID: String?

    enum CodingKeys: String, CodingKey {
        case text
        case definitionID = "definition_id"
    }
}

private struct FreeDictionaryEntryResponse: Decodable {
    let word: String?
    let phonetics: [FreeDictionaryPhonetic]?
    let meanings: [FreeDictionaryMeaning]?
}

private struct FreeDictionaryPhonetic: Decodable {
    let text: String?
}

private struct FreeDictionaryMeaning: Decodable {
    let partOfSpeech: String
    let definitions: [FreeDictionaryDefinition]?
    let synonyms: [String]?
}

private struct FreeDictionaryDefinition: Decodable {
    let definition: String
    let example: String?
    let synonyms: [String]?
}
