import Foundation
import SwiftData

@Model
final class WordRecord {
    @Attribute(.unique) var word: String
    var lookupCount: Int
    var firstLookupDate: Date
    var lastLookupDate: Date
    var lastReviewDate: Date?
    var nextReviewDate: Date?
    var isMastered: Bool
    var reviewStage: Int
    var definitionText: String?
    var sourceLanguageIdentifier: String?

    init(word: String, definitionText: String? = nil, sourceLanguageIdentifier: String? = nil) {
        self.word = word.lowercased()
        self.lookupCount = 1
        self.firstLookupDate = Date()
        self.lastLookupDate = Date()
        self.lastReviewDate = nil
        self.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        self.isMastered = false
        self.reviewStage = 0
        self.definitionText = Self.normalizedDefinitionText(definitionText)
        self.sourceLanguageIdentifier = Self.normalizedLanguageIdentifier(sourceLanguageIdentifier)
    }

    var needsReview: Bool {
        guard !isMastered, let nextReview = nextReviewDate else { return false }
        return nextReview <= Date()
    }

    func recordLookup(definitionText: String? = nil, sourceLanguageIdentifier: String? = nil) {
        lookupCount += 1
        lastLookupDate = Date()
        _ = updateDefinition(definitionText)
        updateSourceLanguage(sourceLanguageIdentifier)
    }

    func updateSourceLanguage(_ identifier: String?) {
        guard let normalized = Self.normalizedLanguageIdentifier(identifier) else { return }
        sourceLanguageIdentifier = normalized
    }

    @discardableResult
    func updateDefinition(_ definitionText: String?) -> Bool {
        guard let normalized = Self.normalizedDefinitionText(definitionText),
              normalized != self.definitionText else {
            return false
        }
        self.definitionText = normalized
        return true
    }

    func advanceReviewStage() {
        lastReviewDate = Date()
        guard reviewStage < EbbinghausInterval.stages.count - 1 else {
            isMastered = true
            nextReviewDate = nil
            return
        }
        reviewStage += 1
        let days = EbbinghausInterval.stages[reviewStage]
        nextReviewDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    func markAsMastered() {
        isMastered = true
        nextReviewDate = nil
    }

    func resetReview() {
        reviewStage = 0
        isMastered = false
        lastReviewDate = nil
        nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
    }

    private static func normalizedDefinitionText(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedLanguageIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum EbbinghausInterval {
    static let stages = [1, 3, 7, 15, 30]

    static func nextReviewDate(for stage: Int) -> Date {
        guard stage < stages.count else { return Date.distantFuture }
        return Calendar.current.date(byAdding: .day, value: stages[stage], to: Date()) ?? Date()
    }
}
