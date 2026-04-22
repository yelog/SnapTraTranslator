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
    private static let englishLetterSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let dominantScriptThreshold = 0.65
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

        let sourceFamily = languageFamily(for: configuredPair.sourceIdentifier)
        let targetFamily = languageFamily(for: configuredPair.targetIdentifier)
        guard sourceFamily != .unknown,
              targetFamily != .unknown,
              sourceFamily != targetFamily else {
            return configuredPair
        }

        guard let observedFamily = observedLanguageFamily(for: observedText) else {
            return configuredPair
        }

        if observedFamily == sourceFamily {
            return configuredPair
        }

        if observedFamily == targetFamily {
            return configuredPair.reversed()
        }

        return configuredPair
    }

    static func supportsBidirectionalDetection(for pair: LookupLanguagePair) -> Bool {
        let sourceFamily = languageFamily(for: pair.sourceIdentifier)
        let targetFamily = languageFamily(for: pair.targetIdentifier)

        return (sourceFamily == .english && targetFamily == .chinese)
            || (sourceFamily == .chinese && targetFamily == .english)
    }

    private enum LanguageFamily {
        case english
        case chinese
        case unknown
    }

    private static func languageFamily(for identifier: String) -> LanguageFamily {
        if identifier.hasPrefix("en") {
            return .english
        }

        if identifier.hasPrefix("zh") {
            return .chinese
        }

        return .unknown
    }

    private static func languageFamily(for script: OCRTokenScript) -> LanguageFamily? {
        switch script {
        case .english:
            return .english
        case .chinese:
            return .chinese
        case .mixed, .unknown:
            return nil
        }
    }

    private static func observedLanguageFamily(for observedText: String) -> LanguageFamily? {
        let filteredText = filteredObservedText(from: observedText)
        let script = OCRTokenClassifier.classify(filteredText)

        if let family = languageFamily(for: script) {
            return family
        }

        guard script == .mixed else {
            return nil
        }

        var chineseCount = 0
        var englishCount = 0

        for scalar in filteredText.unicodeScalars {
            if scalar.properties.isIdeographic {
                chineseCount += 1
            } else if englishLetterSet.contains(scalar) {
                englishCount += 1
            }
        }

        guard chineseCount > 0, englishCount > 0 else {
            return nil
        }

        let dominantCount = max(chineseCount, englishCount)
        let totalCount = chineseCount + englishCount
        let dominantShare = Double(dominantCount) / Double(totalCount)

        guard dominantShare >= dominantScriptThreshold else {
            return nil
        }

        return chineseCount > englishCount ? .chinese : .english
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
