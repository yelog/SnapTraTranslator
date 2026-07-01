import Foundation

struct LookupLanguagePair: Equatable {
    let sourceIdentifier: String
    let targetIdentifier: String

    var key: String {
        "\(sourceIdentifier)->\(targetIdentifier)"
    }

    var sourceLanguage: Locale.Language {
        Locale.Language(identifier: sourceIdentifier)
    }

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetIdentifier)
    }

    var targetIsEnglish: Bool {
        targetLanguage.minimalIdentifier == "en"
    }

    var targetIsChinese: Bool {
        targetLanguage.minimalIdentifier == "zh"
    }

    var isSameLanguage: Bool {
        sourceLanguage.minimalIdentifier == targetLanguage.minimalIdentifier
    }

    static func fixed(sourceIdentifier: String, targetIdentifier: String) -> LookupLanguagePair {
        LookupLanguagePair(
            sourceIdentifier: sourceIdentifier,
            targetIdentifier: targetIdentifier
        )
    }

    func reversed() -> LookupLanguagePair {
        LookupLanguagePair(
            sourceIdentifier: targetIdentifier,
            targetIdentifier: sourceIdentifier
        )
    }

    func directionalPair(targeting requestedTargetIdentifier: String) -> LookupLanguagePair {
        let requestedTargetLanguage = Locale.Language(identifier: requestedTargetIdentifier)

        if requestedTargetLanguage.minimalIdentifier == sourceLanguage.minimalIdentifier {
            return LookupLanguagePair(
                sourceIdentifier: targetIdentifier,
                targetIdentifier: requestedTargetIdentifier
            )
        }

        if requestedTargetLanguage.minimalIdentifier == targetLanguage.minimalIdentifier {
            return LookupLanguagePair(
                sourceIdentifier: sourceIdentifier,
                targetIdentifier: requestedTargetIdentifier
            )
        }

        return LookupLanguagePair(
            sourceIdentifier: sourceIdentifier,
            targetIdentifier: requestedTargetIdentifier
        )
    }
}

enum OCRTokenScript: Equatable {
    case chinese
    case english
    case mixed
    case unknown
}

enum OCRTokenClassifier {
    private static let englishLetterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func classify(_ token: String) -> OCRTokenScript {
        var hanCount = 0
        var englishCount = 0

        for scalar in token.unicodeScalars {
            if scalar.properties.isIdeographic {
                hanCount += 1
            } else if englishLetterSet.contains(scalar) {
                englishCount += 1
            }
        }

        if hanCount > 0 && englishCount == 0 {
            return .chinese
        }

        if englishCount > 0 && hanCount == 0 {
            return .english
        }

        if hanCount > 0 && englishCount > 0 {
            return .mixed
        }

        return .unknown
    }
}

enum LookupLanguagePairResolver {
    private static let englishWordPattern = unsafeRegex(#"[A-Za-z]+(?:'[A-Za-z]+)?"#)
    private static let dominantScriptThreshold = 0.55
    private static let maxEnglishWordWeight = 3
    private static let ignoredObservedTextPatterns: [NSRegularExpression] = [
        unsafeRegex(#"https?://\S+|www\.\S+"#),
        unsafeRegex(#"@[A-Za-z0-9_]+"#),
        unsafeRegex(#"\b\d+(?:[._:/-]\d+)*\b"#),
    ]

    static func resolve(
        configuredPair: LookupLanguagePair,
        observedText: String,
        bidirectionalEnabled: Bool
    ) -> LookupLanguagePair {
        guard bidirectionalEnabled else {
            return configuredPair
        }

        let sourceScript = scriptFamily(for: configuredPair.sourceIdentifier)
        let targetScript = scriptFamily(for: configuredPair.targetIdentifier)
        guard let sourceScript,
              let targetScript,
              sourceScript != targetScript else {
            return configuredPair
        }

        guard let observedScript = observedScriptFamily(for: observedText) else {
            return configuredPair
        }

        if observedScript == sourceScript {
            return configuredPair
        }

        if observedScript == targetScript {
            return configuredPair.reversed()
        }

        return configuredPair
    }

    static func supportsBidirectionalDetection(for pair: LookupLanguagePair) -> Bool {
        guard let sourceScript = scriptFamily(for: pair.sourceIdentifier),
              let targetScript = scriptFamily(for: pair.targetIdentifier) else {
            return false
        }
        return sourceScript != targetScript
    }

    static func shouldLookup(
        configuredPair: LookupLanguagePair,
        observedText: String,
        bidirectionalEnabled: Bool
    ) -> Bool {
        guard !bidirectionalEnabled else { return true }

        let sourceScript = scriptFamily(for: configuredPair.sourceIdentifier)
        let targetScript = scriptFamily(for: configuredPair.targetIdentifier)
        guard let sourceScript,
              let targetScript,
              sourceScript != targetScript,
              let observedScript = observedScriptFamily(for: observedText)
        else {
            return true
        }

        return observedScript == sourceScript
    }

    // MARK: - Script Family Detection

    /// Returns the dominant Unicode script family for a language identifier.
    ///
    /// Uses `Locale.Language.script.identifier` when available, with manual
    /// fallbacks for common CJK and multi-script languages.
    static func scriptFamily(for languageIdentifier: String) -> String? {
        // Manual overrides for well-known multi-script or ambiguous languages
        if languageIdentifier.hasPrefix("zh") {
            return languageIdentifier.contains("Hant") ? "Hant" : "Hans"
        }
        if languageIdentifier.hasPrefix("ja") { return "Jpan" }
        if languageIdentifier.hasPrefix("ko") { return "Kore" }

        let language = Locale.Language(identifier: languageIdentifier)
        if let scriptId = language.script?.identifier, !scriptId.isEmpty {
            return scriptId
        }

        // Fallback: extract 4-letter script subtag from identifier
        // e.g. "sr-Cyrl" → "Cyrl", "uz-Latn" → "Latn"
        let parts = languageIdentifier.split(separator: "-")
        for part in parts where part.count == 4 && part.first?.isUppercase == true {
            return String(part)
        }

        return nil
    }

    /// Returns the dominant Unicode script family for a piece of observed text.
    ///
    /// Counts characters by their Unicode script property and returns the
    /// script with the highest count, applying a dominance threshold for
    /// mixed-script text.
    static func observedScriptFamily(for text: String) -> String? {
        let filteredText = filteredObservedText(from: text)

        var scriptCounts: [String: Int] = [:]
        for scalar in filteredText.unicodeScalars {
            guard let script = scriptName(for: scalar) else { continue }
            scriptCounts[script, default: 0] += 1
        }

        guard !scriptCounts.isEmpty else { return nil }

        let sorted = scriptCounts.sorted { $0.value > $1.value }
        guard let dominant = sorted.first else { return nil }

        let totalCount = sorted.reduce(0) { $0 + $1.value }
        let dominantShare = Double(dominant.value) / Double(totalCount)

        guard dominantShare >= dominantScriptThreshold else {
            return nil
        }

        return dominant.key
    }

    /// Maps a Unicode scalar to its script family name.
    ///
    /// Groups related Unicode blocks into higher-level script families:
    /// - CJK Unified Ideographs → `Hans` (covers both simplified and traditional)
    /// - Hiragana / Katakana → `Jpan`
    /// - Hangul → `Kore`
    /// - Latin / Cyrillic / Arabic / Devanagari / Thai by code point range
    private static func scriptName(for scalar: Unicode.Scalar) -> String? {
        if scalar.properties.isIdeographic {
            return "Hans"
        }

        let cp = scalar.value

        // Hiragana (3040–309F) and Katakana (30A0–30FF, 31F0–31FF, FF65–FF9F)
        if (0x3040...0x309F).contains(cp) || (0x30A0...0x30FF).contains(cp)
            || (0x31F0...0x31FF).contains(cp) || (0xFF65...0xFF9F).contains(cp) {
            return "Jpan"
        }

        // Hangul Syllables (AC00–D7AF), Jamo (1100–11FF), Compatibility Jamo (3130–318F)
        if (0xAC00...0xD7AF).contains(cp) || (0x1100...0x11FF).contains(cp)
            || (0x3130...0x318F).contains(cp) {
            return "Kore"
        }

        // Basic Latin + Latin Extended-A/B + Latin Extended Additional
        if (0x0041...0x024F).contains(cp) || (0x1E00...0x1EFF).contains(cp) {
            return "Latn"
        }

        // Cyrillic + Cyrillic Supplement + Extended-A/B
        if (0x0400...0x052F).contains(cp) || (0x2DE0...0x2DFF).contains(cp)
            || (0xA640...0xA69F).contains(cp) {
            return "Cyrl"
        }

        // Arabic + Arabic Supplement
        if (0x0600...0x06FF).contains(cp) || (0x0750...0x077F).contains(cp) {
            return "Arab"
        }

        // Devanagari
        if (0x0900...0x097F).contains(cp) {
            return "Deva"
        }

        // Thai
        if (0x0E00...0x0E7F).contains(cp) {
            return "Thai"
        }

        return nil
    }

    // MARK: - Mixed Text Helpers

    private static func observedScriptCounts(in text: String) -> (chinese: Int, english: Int) {
        var chineseCount = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isIdeographic {
                chineseCount += 1
            }
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var englishCount = 0
        englishWordPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard
                let match,
                let range = Range(match.range, in: text)
            else {
                return
            }

            let word = text[range]
            let weight = min(word.count, maxEnglishWordWeight)
            englishCount += weight
        }

        return (chinese: chineseCount, english: englishCount)
    }

    private static func filteredObservedText(from observedText: String) -> String {
        ignoredObservedTextPatterns.reduce(observedText) { partialResult, regex in
            let range = NSRange(partialResult.startIndex..<partialResult.endIndex, in: partialResult)
            return regex.stringByReplacingMatches(
                in: partialResult,
                options: [],
                range: range,
                withTemplate: " "
            )
        }
    }

    private static func unsafeRegex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure(error.localizedDescription)
        }
    }
}

enum ImageSentenceTranslationLanguagePairResolver {
    static func resolveManualRegionPair(
        recognizedText: String,
        configuredPair: LookupLanguagePair,
        bidirectionalEnabled: Bool
    ) -> LookupLanguagePair {
        let trimmedText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return configuredPair
        }

        return LookupLanguagePairResolver.resolve(
            configuredPair: configuredPair,
            observedText: trimmedText,
            bidirectionalEnabled: bidirectionalEnabled
        )
    }
}
