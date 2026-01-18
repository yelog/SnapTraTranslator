import CoreServices
import Foundation

final class PhoneticService {
    func phonetic(for word: String) -> String? {
        guard let normalized = normalizeWord(word) else {
            return nil
        }
        let range = CFRange(location: 0, length: normalized.utf16.count)
        guard let definition = DCSCopyTextDefinition(nil, normalized as CFString, range) else {
            return nil
        }
        let html = definition.takeRetainedValue() as String
        return extractPhonetic(from: html)
    }

    private func normalizeWord(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "-'’"))
        let cleaned = firstToken.trimmingCharacters(in: allowed.inverted)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractPhonetic(from html: String) -> String? {
        #if DEBUG
        print("[PhoneticService] Raw HTML (\(html.count) chars):\n\(html.prefix(2000))")
        #endif
        
        let patterns = [
            "<span class=\"pr\">([^<]+)</span>",
            "<span class=\"ipa\">([^<]+)</span>",
            "<span class=\"pron\">([^<]+)</span>",
            "<span class=\"phon\">([^<]+)</span>",
            "<span class=\"pronunciation\">([^<]+)</span>"
        ]
        for pattern in patterns {
            if let match = matchFirst(pattern: pattern, in: html) {
                #if DEBUG
                print("[PhoneticService] Found phonetic with pattern '\(pattern)': \(match)")
                #endif
                return match.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        #if DEBUG
        print("[PhoneticService] No phonetic pattern matched")
        #endif
        return nil
    }

    private func matchFirst(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
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
}
