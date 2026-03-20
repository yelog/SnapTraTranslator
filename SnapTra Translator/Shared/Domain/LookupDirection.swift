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
