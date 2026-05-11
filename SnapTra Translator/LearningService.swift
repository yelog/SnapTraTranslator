import Combine
import Foundation
import SwiftData

enum LearningWordFilter: String, CaseIterable {
    case all = "All"
    case pendingReview = "Pending"
    case mastered = "Mastered"

    var title: String {
        switch self {
        case .all: return L("All Words")
        case .pendingReview: return L("Pending Review")
        case .mastered: return L("Mastered")
        }
    }
}

@MainActor
final class LearningService: ObservableObject {
    private let modelContext: ModelContext

    @Published var visibleWords: [WordRecord] = []
    @Published var totalWordCount = 0
    @Published var pendingReviewCount = 0
    @Published var masteredCount = 0
    @Published var isLoadingPage = false
    @Published var hasMoreWords = false

    private static let wordSortDescriptors = [
        SortDescriptor(\WordRecord.lookupCount, order: .reverse),
        SortDescriptor(\WordRecord.lastLookupDate, order: .reverse),
    ]

    private let pageSize = 100
    private var currentOffset = 0
    private var currentFilter: LearningWordFilter = .all
    private var currentSearchText = ""

    func wordRecord(for word: String) -> WordRecord? {
        visibleWords.first { $0.word == word }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func refreshSummaryCounts() async {
        do {
            totalWordCount = try modelContext.fetchCount(FetchDescriptor<WordRecord>())
            pendingReviewCount = try modelContext.fetchCount(
                FetchDescriptor<WordRecord>(predicate: pendingReviewPredicate(now: Date()))
            )
            masteredCount = try modelContext.fetchCount(
                FetchDescriptor<WordRecord>(predicate: #Predicate { $0.isMastered })
            )
        } catch {
            print("Failed to fetch learning counts: \(error)")
        }
    }

    func reloadWords(filter: LearningWordFilter, searchText: String) async {
        currentFilter = filter
        currentSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        currentOffset = 0
        hasMoreWords = false
        await loadMoreWords(replacingCurrentWords: true)
    }

    func loadMoreWords() async {
        await loadMoreWords(replacingCurrentWords: false)
    }

    private func loadMoreWords(replacingCurrentWords: Bool) async {
        guard !isLoadingPage else { return }
        guard currentOffset == 0 || hasMoreWords else { return }

        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            var descriptor = FetchDescriptor<WordRecord>(
                predicate: listPredicate(
                    filter: currentFilter,
                    searchText: currentSearchText,
                    now: Date()
                ),
                sortBy: Self.wordSortDescriptors
            )
            descriptor.fetchLimit = currentOffset + pageSize + 1

            let records = try modelContext.fetch(descriptor)
            let page = Array(records.dropFirst(currentOffset).prefix(pageSize))
            if replacingCurrentWords {
                visibleWords = page
            } else {
                visibleWords = visibleWords + page
            }
            currentOffset += page.count
            hasMoreWords = records.count > currentOffset
        } catch {
            print("Failed to fetch learning words page: \(error)")
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
        } catch {
            print("Failed to update word definition: \(error)")
        }
    }

    func markAsMastered(_ record: WordRecord) async {
        record.markAsMastered()
        do {
            try modelContext.save()
            await refreshAfterMutation()
        } catch {
            print("Failed to mark word as mastered: \(error)")
        }
    }

    func markAsReviewed(_ record: WordRecord) async {
        record.advanceReviewStage()
        do {
            try modelContext.save()
            await refreshAfterMutation()
        } catch {
            print("Failed to advance review stage: \(error)")
        }
    }

    func resetReview(_ record: WordRecord) async {
        record.resetReview()
        do {
            try modelContext.save()
            await refreshAfterMutation()
        } catch {
            print("Failed to reset review: \(error)")
        }
    }

    func deleteWord(_ record: WordRecord) async {
        modelContext.delete(record)
        do {
            try modelContext.save()
            await refreshAfterMutation()
        } catch {
            print("Failed to delete word record: \(error)")
        }
    }

    func clearAllData() async {
        do {
            try modelContext.delete(model: WordRecord.self)
            try modelContext.save()
            visibleWords = []
            totalWordCount = 0
            pendingReviewCount = 0
            masteredCount = 0
            currentOffset = 0
            hasMoreWords = false
        } catch {
            print("Failed to clear all word records: \(error)")
        }
    }

    func searchWords(query: String) async -> [WordRecord] {
        let normalizedQuery = query.lowercased()
        do {
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: #Predicate { $0.word.contains(normalizedQuery) },
                sortBy: Self.wordSortDescriptors
            )
            return try modelContext.fetch(descriptor)
        } catch {
            print("Failed to search words: \(error)")
            return []
        }
    }

    func exportRows(filter: LearningWordFilter, searchText: String) async -> [LearningExportRow] {
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: listPredicate(filter: filter, searchText: query, now: Date()),
                sortBy: Self.wordSortDescriptors
            )
            return try modelContext.fetch(descriptor).map { LearningExportRow(record: $0) }
        } catch {
            print("Failed to fetch learning export rows: \(error)")
            return []
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

            await refreshAfterMutation()
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

    private func refreshAfterMutation() async {
        await refreshSummaryCounts()
        await reloadWords(filter: currentFilter, searchText: currentSearchText)
    }

    private func pendingReviewPredicate(now: Date) -> Predicate<WordRecord> {
        #Predicate { record in
            if let nextReviewDate = record.nextReviewDate {
                !record.isMastered && nextReviewDate <= now
            } else {
                false
            }
        }
    }

    private func listPredicate(
        filter: LearningWordFilter,
        searchText: String,
        now: Date
    ) -> Predicate<WordRecord>? {
        let query = searchText
        switch (filter, query.isEmpty) {
        case (.all, true):
            return nil
        case (.all, false):
            return #Predicate { $0.word.contains(query) }
        case (.pendingReview, true):
            return pendingReviewPredicate(now: now)
        case (.pendingReview, false):
            return #Predicate { record in
                if let nextReviewDate = record.nextReviewDate {
                    record.word.contains(query) && !record.isMastered && nextReviewDate <= now
                } else {
                    false
                }
            }
        case (.mastered, true):
            return #Predicate { $0.isMastered }
        case (.mastered, false):
            return #Predicate { $0.isMastered && $0.word.contains(query) }
        }
    }
}
