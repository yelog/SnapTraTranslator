import Combine
import Foundation
import SwiftData

@MainActor
final class LearningService: ObservableObject {
    private let modelContext: ModelContext

    @Published var allWords: [WordRecord] = []
    @Published var pendingReviewWords: [WordRecord] = []
    @Published var masteredWords: [WordRecord] = []

    var totalWordCount: Int { allWords.count }
    var pendingReviewCount: Int { pendingReviewWords.count }
    var masteredCount: Int { masteredWords.count }

    func wordRecord(for word: String) -> WordRecord? {
        allWords.first { $0.word == word }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refreshWords() async {
        do {
            let descriptor = FetchDescriptor<WordRecord>(
                sortBy: [SortDescriptor(\.lookupCount, order: .reverse)]
            )
            allWords = try modelContext.fetch(descriptor)

            pendingReviewWords = allWords.filter { $0.needsReview }
            masteredWords = allWords.filter { $0.isMastered }
        } catch {
            print("Failed to fetch word records: \(error)")
        }
    }

    func recordLookup(word: String, definitionText: String? = nil) async {
        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWord.isEmpty else { return }

        do {
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: #Predicate { $0.word == normalizedWord }
            )
            let existing = try modelContext.fetch(descriptor).first

            if let record = existing {
                record.recordLookup(definitionText: definitionText)
            } else {
                let newRecord = WordRecord(word: normalizedWord, definitionText: definitionText)
                modelContext.insert(newRecord)
            }

            try modelContext.save()
        } catch {
            print("Failed to record word lookup: \(error)")
        }
    }

    func updateDefinition(word: String, definitionText: String?) async {
        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWord.isEmpty else { return }

        do {
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: #Predicate { $0.word == normalizedWord }
            )
            if let record = try modelContext.fetch(descriptor).first {
                record.updateDefinition(definitionText)
            } else {
                modelContext.insert(WordRecord(word: normalizedWord, definitionText: definitionText))
            }

            try modelContext.save()
            await refreshWords()
        } catch {
            print("Failed to update word definition: \(error)")
        }
    }

    func markAsMastered(_ record: WordRecord) async {
        record.markAsMastered()
        do {
            try modelContext.save()
            await refreshWords()
        } catch {
            print("Failed to mark word as mastered: \(error)")
        }
    }

    func markAsReviewed(_ record: WordRecord) async {
        record.advanceReviewStage()
        do {
            try modelContext.save()
            await refreshWords()
        } catch {
            print("Failed to advance review stage: \(error)")
        }
    }

    func resetReview(_ record: WordRecord) async {
        record.resetReview()
        do {
            try modelContext.save()
            await refreshWords()
        } catch {
            print("Failed to reset review: \(error)")
        }
    }

    func deleteWord(_ record: WordRecord) async {
        modelContext.delete(record)
        do {
            try modelContext.save()
            await refreshWords()
        } catch {
            print("Failed to delete word record: \(error)")
        }
    }

    func clearAllData() async {
        do {
            try modelContext.delete(model: WordRecord.self)
            try modelContext.save()
            await refreshWords()
        } catch {
            print("Failed to clear all word records: \(error)")
        }
    }

    func searchWords(query: String) async -> [WordRecord] {
        guard !query.isEmpty else { return allWords }

        let normalizedQuery = query.lowercased()
        do {
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: #Predicate { $0.word.contains(normalizedQuery) },
                sortBy: [SortDescriptor(\.lookupCount, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            print("Failed to search words: \(error)")
            return allWords.filter { $0.word.contains(normalizedQuery) }
        }
    }

    func cleanupOldRecords(maxRecords: Int, cleanupDays: Int) async -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -cleanupDays, to: Date()) ?? Date()
        var deletedCount = 0

        do {
            let masteredDescriptor = FetchDescriptor<WordRecord>(
                predicate: #Predicate { $0.isMastered && $0.lastLookupDate < cutoffDate }
            )
            let masteredRecords = try modelContext.fetch(masteredDescriptor)
            for record in masteredRecords {
                if record.lastReviewDate == nil || record.lastReviewDate! < cutoffDate {
                    modelContext.delete(record)
                    deletedCount += 1
                }
            }

            try modelContext.save()

            let countDescriptor = FetchDescriptor<WordRecord>()
            let totalCount = try modelContext.fetchCount(countDescriptor)

            if totalCount > maxRecords {
                let excessCount = totalCount - maxRecords
                var oldestDescriptor = FetchDescriptor<WordRecord>(
                    sortBy: [
                        SortDescriptor(\.lookupCount, order: .forward),
                        SortDescriptor(\.lastLookupDate, order: .forward)
                    ]
                )
                oldestDescriptor.fetchLimit = excessCount
                let oldestRecords = try modelContext.fetch(oldestDescriptor)
                for record in oldestRecords {
                    modelContext.delete(record)
                    deletedCount += 1
                }
                try modelContext.save()
            }

            await refreshWords()
        } catch {
            print("Failed to cleanup old records: \(error)")
        }

        return deletedCount
    }

    func fetchTotalCount() async -> Int {
        do {
            let descriptor = FetchDescriptor<WordRecord>()
            return try modelContext.fetchCount(descriptor)
        } catch {
            print("Failed to fetch count: \(error)")
            return 0
        }
    }
}
