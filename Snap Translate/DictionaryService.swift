import CoreServices
import Foundation

/// 词典服务，从 macOS 系统词典获取单词的完整信息
final class DictionaryService {

    /// 查询单词的词典信息
    func lookup(_ word: String) -> DictionaryEntry? {
        guard let normalized = normalizeWord(word) else {
            return nil
        }

        let range = CFRange(location: 0, length: normalized.utf16.count)
        guard let definition = DCSCopyTextDefinition(nil, normalized as CFString, range) else {
            return nil
        }

        let html = definition.takeRetainedValue() as String

        #if DEBUG
        print("[DictionaryService] Raw HTML for '\(normalized)' (\(html.count) chars):\n\(html.prefix(3000))")
        #endif

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
        let posGroups = extractPartOfSpeechGroups(from: html)

        if !posGroups.isEmpty {
            for (pos, content) in posGroups {
                let meanings = extractMeanings(from: content)
                let examples = extractExamples(from: content)

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
            let allMeanings = extractAllMeanings(from: html)
            let allExamples = extractExamples(from: html)

            for meaning in allMeanings.prefix(3) {
                definitions.append(DictionaryEntry.Definition(
                    partOfSpeech: "",
                    meaning: meaning,
                    translation: nil,
                    examples: allExamples
                ))
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
            "<b>\\s*(noun|verb|adjective|adverb|preposition|conjunction|pronoun|interjection|n\\.|v\\.|adj\\.|adv\\.)\\s*</b>"
        ]

        let knownPOS = ["noun", "verb", "adjective", "adverb", "preposition", "conjunction",
                        "pronoun", "interjection", "n.", "v.", "adj.", "adv.", "n", "v", "adj", "adv",
                        "名词", "动词", "形容词", "副词"]

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
                let isValidPOS = knownPOS.contains { pos.contains($0.lowercased()) }
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
