import Foundation
import SwiftData

@Model
final class WordRecord {
    @Attribute(.unique) var word: String
    var lookupCount: Int
    var firstLookupDate: Date
    var lastLookupDate: Date
    var nextReviewDate: Date?
    var isMastered: Bool
    var reviewStage: Int

    init(word: String) {
        self.word = word.lowercased()
        self.lookupCount = 1
        self.firstLookupDate = Date()
        self.lastLookupDate = Date()
        self.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        self.isMastered = false
        self.reviewStage = 0
    }

    var needsReview: Bool {
        guard !isMastered, let nextReview = nextReviewDate else { return false }
        return nextReview <= Date()
    }

    func recordLookup() {
        lookupCount += 1
        lastLookupDate = Date()
    }

    func advanceReviewStage() {
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
        nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
    }
}

enum EbbinghausInterval {
    static let stages = [1, 3, 7, 15, 30]

    static func nextReviewDate(for stage: Int) -> Date {
        guard stage < stages.count else { return Date.distantFuture }
        return Calendar.current.date(byAdding: .day, value: stages[stage], to: Date()) ?? Date()
    }
}