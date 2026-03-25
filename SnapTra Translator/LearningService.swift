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

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await refreshWords()
        }
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

    func recordLookup(word: String) async {
        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWord.isEmpty else { return }

        do {
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: #Predicate { $0.word == normalizedWord }
            )
            let existing = try modelContext.fetch(descriptor).first

            if let record = existing {
                record.recordLookup()
            } else {
                let newRecord = WordRecord(word: normalizedWord)
                modelContext.insert(newRecord)
            }

            try modelContext.save()
            await refreshWords()
        } catch {
            print("Failed to record word lookup: \(error)")
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
        return allWords.filter { $0.word.contains(normalizedQuery) }
    }
}