import CoreServices
import Foundation

final class DictionaryService {
    func lookup(_ word: String, preferEnglish: Bool = false) -> DictionaryEntry? {
        
        guard let normalized = normalizeWord(word) else {
            return nil
        }
        
        let range = CFRange(location: 0, length: normalized.utf16.count)
        
        guard let definition = DCSCopyTextDefinition(nil, normalized as CFString, range) else {
            return nil
        }

        let html = definition.takeRetainedValue() as String

        #if DEBUG
        print("[DictionaryService] Default dictionary result for '\(normalized)' (\(html.count) chars):\n\(html.prefix(2000))")
        #endif

        if preferEnglish {
            return parseEnglishHTML(html, word: normalized)
        }

        return parseHTML(html, word: normalized)
    }

    // MARK: - Private

    private func normalizeWord(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "-''"))
        let cleaned = firstToken.trimmingCharacters(in: allowed.inverted)
        return cleaned.isEmpty ? nil : cleaned.lowercased()
    }

    private func parseHTML(_ html: String, word: String) -> DictionaryEntry {
        let phonetic = extractPhonetic(from: html)
        let definitions = extractDefinitions(from: html)

        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            definitions: definitions
        )
    }
    
    private func parseEnglishHTML(_ html: String, word: String) -> DictionaryEntry {
        let phonetic = extractPhonetic(from: html)
        let definitions = extractEnglishDefinitions(from: html)

        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            definitions: definitions
        )
    }
    
    private func extractEnglishDefinitions(from html: String) -> [DictionaryEntry.Definition] {
        var definitions: [DictionaryEntry.Definition] = []
        let text = stripHTML(html)
        
        let posPattern = "(plural noun|noun|verb|adjective|adverb|preposition|conjunction|pronoun|interjection)"
        guard let posRegex = try? NSRegularExpression(pattern: posPattern, options: .caseInsensitive) else {
            return definitions
        }
        
        let posMatches = posRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        for (index, match) in posMatches.enumerated() {
            guard let posRange = Range(match.range, in: text) else { continue }
            let pos = normalizePOS(String(text[posRange]))
            
            let contentStart = posRange.upperBound
            let contentEnd: String.Index
            if index + 1 < posMatches.count, let nextRange = Range(posMatches[index + 1].range, in: text) {
                contentEnd = nextRange.lowerBound
            } else {
                let phrasesRange = text.range(of: "PHRASES", options: .caseInsensitive, range: contentStart..<text.endIndex)
                let originRange = text.range(of: "ORIGIN", options: .caseInsensitive, range: contentStart..<text.endIndex)
                if let phrases = phrasesRange, let origin = originRange {
                    contentEnd = min(phrases.lowerBound, origin.lowerBound)
                } else {
                    contentEnd = phrasesRange?.lowerBound ?? originRange?.lowerBound ?? text.endIndex
                }
            }
            
            let content = String(text[contentStart..<contentEnd])
            
            let numberedPattern = "(?:^|\\s)(\\d+)\\s+(.+?)(?=(?:\\s+\\d+\\s+)|$)"
            guard let numRegex = try? NSRegularExpression(pattern: numberedPattern, options: [.dotMatchesLineSeparators]) else { continue }
            
            let numMatches = numRegex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
            
            for numMatch in numMatches {
                guard numMatch.numberOfRanges >= 3,
                      let meaningRange = Range(numMatch.range(at: 2), in: content) else { continue }
                
                var meaning = String(content[meaningRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                meaning = cleanEnglishDefinition(meaning)
                
                if meaning.count > 5, meaning.range(of: "[a-zA-Z]{3,}", options: .regularExpression) != nil {
                    definitions.append(DictionaryEntry.Definition(
                        partOfSpeech: pos,
                        meaning: meaning,
                        translation: meaning,
                        examples: []
                    ))
                }
            }
            
            if numMatches.isEmpty {
                var meaning = content.trimmingCharacters(in: .whitespacesAndNewlines)
                meaning = cleanEnglishDefinition(meaning)
                
                if meaning.count > 5, meaning.range(of: "[a-zA-Z]{3,}", options: .regularExpression) != nil {
                    definitions.append(DictionaryEntry.Definition(
                        partOfSpeech: pos,
                        meaning: meaning,
                        translation: meaning,
                        examples: []
                    ))
                }
            }
        }
        
        if definitions.isEmpty {
            let fallbackDefs = extractFallbackEnglishDefinitions(from: text)
            definitions.append(contentsOf: fallbackDefs)
        }
        
        return definitions
    }
    
    private func cleanEnglishDefinition(_ text: String) -> String {
        var result = text
        
        if let colonIndex = result.firstIndex(of: ":") {
            result = String(result[..<colonIndex])
        }
        
        result = result.replacingOccurrences(of: "\\s*\\|.*", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func detectPartOfSpeech(_ text: String) -> String? {
        let posPatterns = [
            "^(noun|verb|adjective|adverb|preposition|conjunction|pronoun|interjection)\\s*$",
            "^(n\\.|v\\.|adj\\.|adv\\.|prep\\.|conj\\.|pron\\.|interj\\.)\\s*$"
        ]
        
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in posPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: lowercased, options: [], range: NSRange(lowercased.startIndex..., in: lowercased)) != nil {
                return normalizePOS(lowercased)
            }
        }
        return nil
    }
    
    private func extractNumberedMeaning(_ text: String) -> (Int, String)? {
        let pattern = "^(\\d+)\\s+(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 3,
              let numRange = Range(match.range(at: 1), in: text),
              let meaningRange = Range(match.range(at: 2), in: text),
              let number = Int(String(text[numRange])) else {
            return nil
        }
        return (number, String(text[meaningRange]))
    }
    
    private func cleanEnglishMeaning(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: ":\\s*$", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s*\\|.*$", with: "", options: .regularExpression)
        
        if let colonIndex = result.firstIndex(of: ":") {
            result = String(result[..<colonIndex])
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractFallbackEnglishDefinitions(from text: String) -> [DictionaryEntry.Definition] {
        var definitions: [DictionaryEntry.Definition] = []
        
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".;"))
        var currentPOS = ""
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 10, trimmed.count < 200 else { continue }
            
            let containsChinese = trimmed.range(of: "\\p{Han}", options: .regularExpression) != nil
            guard !containsChinese else { continue }
            
            if let pos = detectPartOfSpeech(trimmed) {
                currentPOS = pos
                continue
            }
            
            let hasEnglishContent = trimmed.range(of: "[a-zA-Z]{4,}", options: .regularExpression) != nil
            if hasEnglishContent {
                definitions.append(DictionaryEntry.Definition(
                    partOfSpeech: currentPOS,
                    meaning: trimmed,
                    translation: trimmed,
                    examples: []
                ))
                if definitions.count >= 3 {
                    break
                }
            }
        }
        
        return definitions
    }

    // MARK: - Phonetic Extraction

    private func extractPhonetic(from html: String) -> String? {
        let patterns = [
            "<span[^>]*class=\"[^\"]*pr[^\"]*\"[^>]*>([^<]+)</span>",
            "<span[^>]*class=\"[^\"]*ipa[^\"]*\"[^>]*>([^<]+)</span>",
            "<span[^>]*class=\"[^\"]*pron[^\"]*\"[^>]*>([^<]+)</span>",
            "<span[^>]*class=\"[^\"]*phon[^\"]*\"[^>]*>([^<]+)</span>",
            "\\|([^|]+)\\|",  // |phonetic| 格式
            "/([^/]+)/"       // /phonetic/ 格式
        ]

        for pattern in patterns {
            if let match = matchFirst(pattern: pattern, in: html) {
                let cleaned = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }

    // MARK: - Definition Extraction

    private func extractDefinitions(from html: String) -> [DictionaryEntry.Definition] {
        var definitions: [DictionaryEntry.Definition] = []

        // 尝试提取词性分组
        var posGroups = extractPartOfSpeechGroups(from: html)
        if posGroups.isEmpty {
            posGroups = extractPlainTextPartOfSpeechGroups(from: html)
        }

        if !posGroups.isEmpty {
            for (pos, content) in posGroups {
                let examples = extractExamples(from: content)

                if !content.contains("<") {
                    let plainMeanings = extractPlainTextMeanings(from: content)
                    if !plainMeanings.isEmpty {
                        for meaning in plainMeanings {
                            definitions.append(DictionaryEntry.Definition(
                                partOfSpeech: pos,
                                meaning: meaning.meaning,
                                translation: meaning.translation,
                                examples: []
                            ))
                        }
                        continue
                    }
                }

                let meanings = extractMeanings(from: content)
                if !meanings.isEmpty {
                    for meaning in meanings {
                        definitions.append(DictionaryEntry.Definition(
                            partOfSpeech: pos,
                            meaning: meaning,
                            translation: nil,
                            examples: examples
                        ))
                    }
                } else {
                    // 如果没有提取到具体释义，使用整个内容作为释义
                    let plainContent = stripHTML(content)
                    if !plainContent.isEmpty {
                        definitions.append(DictionaryEntry.Definition(
                            partOfSpeech: pos,
                            meaning: plainContent,
                            translation: nil,
                            examples: examples
                        ))
                    }
                }
            }
        }

        // 如果没有提取到词性分组，尝试直接提取释义
        if definitions.isEmpty {
            let fallbackPOS = extractPlainTextPartOfSpeech(from: html) ?? ""
            let plainMeanings = extractPlainTextMeanings(from: html)
            if !plainMeanings.isEmpty {
                for meaning in plainMeanings.prefix(3) {
                    definitions.append(DictionaryEntry.Definition(
                        partOfSpeech: fallbackPOS,
                        meaning: meaning.meaning,
                        translation: meaning.translation,
                        examples: []
                    ))
                }
            } else {
                let allMeanings = extractAllMeanings(from: html)
                let allExamples = extractExamples(from: html)

                for meaning in allMeanings.prefix(3) {
                    definitions.append(DictionaryEntry.Definition(
                        partOfSpeech: fallbackPOS,
                        meaning: meaning,
                        translation: nil,
                        examples: allExamples
                    ))
                }
            }
        }

        return definitions
    }

    private func extractPartOfSpeechGroups(from html: String) -> [(String, String)] {
        var groups: [(String, String)] = []

        // 匹配词性标签及其后续内容
        let posPatterns = [
            // 匹配 <span class="posg">noun</span> 或类似格式
            "<span[^>]*class=\"[^\"]*(?:posg|pos|fg)[^\"]*\"[^>]*>([^<]+)</span>",
            // 匹配 <b>noun</b> 格式
            "<b>\\s*(transitive verb|intransitive verb|vt\\.?|vi\\.?|noun|verb|adjective|adverb|preposition|conjunction|pronoun|interjection|n\\.|v\\.|adj\\.|adv\\.)\\s*</b>"
        ]

        for pattern in posPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            let matches = regex.matches(in: html, options: [], range: range)

            for (index, match) in matches.enumerated() {
                guard match.numberOfRanges > 1,
                      let posRange = Range(match.range(at: 1), in: html) else {
                    continue
                }

                let pos = String(html[posRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                // 验证是否为有效词性
                let isValidPOS = isValidPartOfSpeech(pos)
                guard isValidPOS else { continue }

                // 获取该词性后面的内容（直到下一个词性或结束）
                let startIndex = match.range.upperBound
                let endIndex: Int
                if index + 1 < matches.count {
                    endIndex = matches[index + 1].range.lowerBound
                } else {
                    endIndex = html.utf16.count
                }

                if startIndex < endIndex,
                   let contentStartIndex = html.index(html.startIndex, offsetBy: startIndex, limitedBy: html.endIndex),
                   let contentEndIndex = html.index(html.startIndex, offsetBy: min(endIndex, html.utf16.count), limitedBy: html.endIndex) {
                    let content = String(html[contentStartIndex..<contentEndIndex])
                    groups.append((normalizePOS(pos), content))
                }
            }

            if !groups.isEmpty {
                break
            }
        }

        return groups
    }

    private func normalizePOS(_ pos: String) -> String {
        let lowercased = pos.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lowercased {
        case "n", "n.", "noun", "名词": return "n."
        case "vt", "vt.", "transitive verb", "及物动词": return "vt."
        case "vi", "vi.", "intransitive verb", "不及物动词": return "vi."
        case "v", "v.", "verb", "动词": return "v."
        case "adj", "adj.", "adjective", "形容词": return "adj."
        case "adv", "adv.", "adverb", "副词": return "adv."
        case "prep", "prep.", "preposition": return "prep."
        case "conj", "conj.", "conjunction": return "conj."
        case "pron", "pron.", "pronoun": return "pron."
        case "interj", "interj.", "interjection": return "interj."
        default: return lowercased
        }
    }

    private struct PlainTextMeaning {
        let meaning: String
        let translation: String?
    }

    private func extractPlainTextPartOfSpeech(from html: String) -> String? {
        let text = stripHTML(html)
        guard !text.isEmpty else { return nil }
        let header = splitPlainTextSenses(text).first ?? text
        if let headerPOS = findFirstPartOfSpeech(in: header) {
            return headerPOS
        }
        return findFirstPartOfSpeech(in: text)
    }

    private func findFirstPartOfSpeech(in text: String) -> String? {
        guard let range = findFirstPartOfSpeechRange(in: text) else { return nil }
        let label = String(text[range])
        return normalizePOS(label)
    }

    private func findFirstPartOfSpeechRange(in text: String) -> Range<String.Index>? {
        let pattern = "(transitive verb|intransitive verb|vt\\.?|vi\\.?|noun|verb|adjective|adverb|preposition|conjunction|pronoun|interjection|n\\.|v\\.|adj\\.|adv\\.|名词|动词|形容词|副词|及物动词|不及物动词)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return matchRange
    }

    private func isHeaderLine(_ text: String) -> Bool {
        text.contains("BrE") || text.contains("AmE")
    }

    private func extractPlainTextPartOfSpeechGroups(from html: String) -> [(String, String)] {
        let text = stripHTML(html)
        guard !text.isEmpty else { return [] }
        guard let regex = try? NSRegularExpression(pattern: "(?:^|[^A-Za-z])([A-Z])\\.", options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        var groups: [(String, String)] = []
        if !matches.isEmpty {
            for (index, match) in matches.enumerated() {
                let startIndex = match.range.upperBound
                guard let contentStart = text.index(text.startIndex, offsetBy: startIndex, limitedBy: text.endIndex) else {
                    continue
                }
                let (posLabel, posEndIndex) = parsePOSLabel(in: text, from: contentStart)
                let normalizedPOS = normalizePOS(posLabel)
                guard isValidPartOfSpeech(posLabel), !normalizedPOS.isEmpty else { continue }

                let contentStartIndex = skipWhitespace(in: text, from: posEndIndex)
                let endIndex: Int
                if index + 1 < matches.count {
                    endIndex = matches[index + 1].range.lowerBound
                } else {
                    endIndex = text.utf16.count
                }

                if let contentEndIndex = text.index(text.startIndex, offsetBy: min(endIndex, text.utf16.count), limitedBy: text.endIndex),
                   contentStartIndex < contentEndIndex {
                    let content = String(text[contentStartIndex..<contentEndIndex])
                    groups.append((normalizedPOS, content))
                }
            }
        }

        if !groups.isEmpty {
            return groups
        }

        if let posRange = findFirstPartOfSpeechRange(in: text) {
            let posLabel = String(text[posRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPOS = normalizePOS(posLabel)
            let contentStartIndex = skipWhitespace(in: text, from: posRange.upperBound)
            let content = String(text[contentStartIndex...])
            if !content.isEmpty, isValidPartOfSpeech(posLabel) {
                return [(normalizedPOS, content)]
            }
        }

        return []
    }

    private func extractPlainTextMeanings(from html: String) -> [PlainTextMeaning] {
        let text = stripHTML(html)
        var senses = splitPlainTextSenses(text)
        guard !senses.isEmpty else { return [] }

        if let first = senses.first, isHeaderLine(first) {
            senses.removeFirst()
        }

        var meanings: [PlainTextMeaning] = []
        for sense in senses {
            let trimmed = sense.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let content = trimmed.components(separatedBy: "▸").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
            let parsed = splitMeaningAndTranslation(from: content)
            if parsed.meaning.count > 2 {
                meanings.append(parsed)
            }
        }
        return meanings
    }

    private func splitPlainTextSenses(_ text: String) -> [String] {
        let markers = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]
        var senses: [String] = []
        var current = ""

        for character in text {
            if markers.contains(String(character)) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    senses.append(trimmed)
                }
                current = ""
            } else {
                current.append(character)
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            senses.append(trimmed)
        }

        return senses
    }

    private func splitMeaningAndTranslation(from text: String) -> PlainTextMeaning {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "\\p{Han}", options: .regularExpression) else {
            return PlainTextMeaning(meaning: trimmed, translation: nil)
        }
        let englishPart = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let chinesePart = String(trimmed[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !englishPart.isEmpty else {
            return PlainTextMeaning(meaning: trimmed, translation: nil)
        }
        let cleanedTranslation = sanitizePlainTextTranslation(chinesePart)
        return PlainTextMeaning(meaning: englishPart, translation: cleanedTranslation.isEmpty ? nil : cleanedTranslation)
    }

    private func sanitizePlainTextTranslation(_ text: String) -> String {
        var result = text
        let latinPattern = "[A-Za-z\\u00C0-\\u024F\\u1E00-\\u1EFF]+"
        result = result.replacingOccurrences(of: "«[^»]*»", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "‹[^›]*›", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\([^\\)]*[A-Za-z\\u00C0-\\u024F\\u1E00-\\u1EFF][^\\)]*\\)", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: latinPattern, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsePOSLabel(in text: String, from startIndex: String.Index) -> (String, String.Index) {
        var index = skipWhitespace(in: text, from: startIndex)
        let labelStart = index

        while index < text.endIndex {
            let character = text[index]
            if isPOSLabelCharacter(character) {
                index = text.index(after: index)
            } else {
                break
            }
        }

        let rawLabel = String(text[labelStart..<index]).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let normalizedLabel = normalizePOSLabel(rawLabel)
        let labelEndIndex = text.index(labelStart, offsetBy: normalizedLabel.count, limitedBy: index) ?? index
        return (normalizedLabel, labelEndIndex)
    }

    private func normalizePOSLabel(_ label: String) -> String {
        let lowercased = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["transitive verb", "intransitive verb", "vt", "vi", "noun", "verb", "adjective", "adverb",
                        "preposition", "conjunction", "pronoun", "interjection", "n.", "v.", "adj.", "adv.",
                        "n", "v", "adj", "adv", "名词", "动词", "形容词", "副词", "及物动词", "不及物动词"]
        for prefix in prefixes {
            if lowercased.hasPrefix(prefix) {
                return prefix
            }
        }
        if let range = findFirstPartOfSpeechRange(in: label) {
            return String(label[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func skipWhitespace(in text: String, from index: String.Index) -> String.Index {
        var currentIndex = index
        while currentIndex < text.endIndex, text[currentIndex].isWhitespace {
            currentIndex = text.index(after: currentIndex)
        }
        return currentIndex
    }

    private func isPOSLabelCharacter(_ character: Character) -> Bool {
        if character == "." || character == "-" {
            return true
        }
        if character.isWhitespace {
            return true
        }
        return character.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    private func isValidPartOfSpeech(_ pos: String) -> Bool {
        let lowercased = pos.lowercased()
        let knownPOS = ["noun", "verb", "adjective", "adverb", "preposition", "conjunction",
                        "pronoun", "interjection", "transitive verb", "intransitive verb", "vt", "vi",
                        "n.", "v.", "adj.", "adv.", "n", "v", "adj", "adv", "名词", "动词", "形容词", "副词", "及物动词", "不及物动词"]
        return knownPOS.contains { lowercased.contains($0) }
    }

    private func extractMeanings(from html: String) -> [String] {
        var meanings: [String] = []

        // 匹配释义标签
        let patterns = [
            "<span[^>]*class=\"[^\"]*(?:df|def|definition|meaning)[^\"]*\"[^>]*>([^<]+(?:<[^>]+>[^<]*</[^>]+>)?[^<]*)</span>",
            "<div[^>]*class=\"[^\"]*(?:df|def|definition|meaning)[^\"]*\"[^>]*>([^<]+)</div>"
        ]

        for pattern in patterns {
            let matches = matchAll(pattern: pattern, in: html)
            for match in matches {
                let cleaned = stripHTML(match).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count > 2 {
                    meanings.append(cleaned)
                }
            }
            if !meanings.isEmpty {
                break
            }
        }

        return meanings
    }

    private func extractAllMeanings(from html: String) -> [String] {
        var meanings: [String] = []

        // 尝试多种方式提取释义
        let patterns = [
            "<span[^>]*class=\"[^\"]*(?:df|def)[^\"]*\"[^>]*>([^<]+)</span>",
            "<d:def[^>]*>([^<]+)</d:def>"
        ]

        for pattern in patterns {
            let matches = matchAll(pattern: pattern, in: html)
            for match in matches {
                let cleaned = stripHTML(match).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count > 3 {
                    meanings.append(cleaned)
                }
            }
        }

        // 如果还是没有，尝试从纯文本中提取
        if meanings.isEmpty {
            let plainText = stripHTML(html)
            let sentences = plainText.components(separatedBy: CharacterSet(charactersIn: ".;"))
            for sentence in sentences.prefix(3) {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 10 && trimmed.count < 200 {
                    meanings.append(trimmed + ".")
                    break
                }
            }
        }

        return meanings
    }

    private func extractExamples(from html: String) -> [String] {
        var examples: [String] = []

        // 匹配例句标签
        let patterns = [
            "<span[^>]*class=\"[^\"]*(?:eg|ex|example)[^\"]*\"[^>]*>([^<]+)</span>",
            "<i>([^<]+)</i>",  // 斜体通常是例句
            "[\u{201C}\u{201D}]([^\u{201C}\u{201D}]+)[\u{201C}\u{201D}]"  // 引号内的内容
        ]

        for pattern in patterns {
            let matches = matchAll(pattern: pattern, in: html)
            for match in matches {
                let cleaned = match.trimmingCharacters(in: .whitespacesAndNewlines)
                // 例句通常较长，且包含空格
                if cleaned.count > 10 && cleaned.contains(" ") {
                    examples.append(cleaned)
                    if examples.count >= 2 {
                        break
                    }
                }
            }
            if !examples.isEmpty {
                break
            }
        }

        return examples
    }

    // MARK: - Helpers

    private func matchFirst(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
            return nil
        }
        guard let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    private func matchAll(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[matchRange])
        }
    }

    private func stripHTML(_ html: String) -> String {
        // 移除 HTML 标签
        var result = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // 解码 HTML 实体
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        // 压缩空白
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
