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

enum LearningLanguageDisplay {
    static func name(for identifier: String?) -> String {
        guard let identifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return L("Unknown")
        }

        return AppLanguage(rawValue: identifier)?.displayName
            ?? Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }
}

@MainActor
final class LearningService: ObservableObject {
    private let modelContext: ModelContext

    @Published var visibleWords: [WordRecord] = []
    @Published var visibleRows: [WordRecordRowModel] = []
    @Published var totalWordCount = 0
    @Published var pendingReviewCount = 0
    @Published var masteredCount = 0
    @Published var isLoadingPage = false
    @Published var hasMoreWords = false
    @Published var availableLanguageIdentifiers: [String] = []

    private static let wordSortDescriptors = [
        SortDescriptor(\WordRecord.lookupCount, order: .reverse),
        SortDescriptor(\WordRecord.lastLookupDate, order: .reverse),
        SortDescriptor(\WordRecord.word, order: .forward),
    ]

    private let pageSize = 100
    private var currentOffset = 0
    private var currentFilter: LearningWordFilter = .all
    private var currentSearchText = ""
    private var currentSourceLanguageIdentifier: String?

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

    func refreshAvailableLanguageIdentifiers() async {
        do {
            let descriptor = FetchDescriptor<WordRecord>(
                sortBy: [SortDescriptor(\WordRecord.sourceLanguageIdentifier)]
            )
            let records = try modelContext.fetch(descriptor)
            var seenIdentifiers = Set<String>()
            availableLanguageIdentifiers = records.reduce(into: []) { result, record in
                guard let identifier = record.sourceLanguageIdentifier,
                      !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      seenIdentifiers.insert(identifier).inserted else {
                    return
                }
                result.append(identifier)
            }
        } catch {
            print("Failed to fetch learning language identifiers: \(error)")
        }
    }

    func reloadWords(filter: LearningWordFilter, searchText: String, sourceLanguageIdentifier: String? = nil) async {
        currentFilter = filter
        currentSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        currentSourceLanguageIdentifier = Self.normalizedLanguageIdentifier(sourceLanguageIdentifier)
        currentOffset = 0
        hasMoreWords = false
        visibleWords = []
        visibleRows = []
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
                    sourceLanguageIdentifier: currentSourceLanguageIdentifier,
                    now: Date()
                ),
                sortBy: Self.wordSortDescriptors
            )
            descriptor.fetchOffset = currentOffset
            descriptor.fetchLimit = pageSize + 1

            let records = try modelContext.fetch(descriptor)
            let page = Array(records.prefix(pageSize))
            let now = Date()
            let pageRows = page.map { WordRecordRowModel(record: $0, now: now) }
            if replacingCurrentWords {
                visibleWords = page
                visibleRows = pageRows
            } else {
                visibleWords.append(contentsOf: page)
                visibleRows.append(contentsOf: pageRows)
            }
            currentOffset += page.count
            hasMoreWords = records.count > pageSize
        } catch {
            print("Failed to fetch learning words page: \(error)")
        }
    }

    func recordLookup(word: String, definitionText: String? = nil, sourceLanguageIdentifier: String? = nil) async {
        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWord.isEmpty else { return }
        let normalizedLanguage = Self.normalizedLanguageIdentifier(sourceLanguageIdentifier)

        do {
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: #Predicate { $0.word == normalizedWord }
            )
            let existing = try modelContext.fetch(descriptor).first

            if let record = existing {
                record.recordLookup(definitionText: definitionText, sourceLanguageIdentifier: normalizedLanguage)
            } else {
                let newRecord = WordRecord(
                    word: normalizedWord,
                    definitionText: definitionText,
                    sourceLanguageIdentifier: normalizedLanguage
                )
                modelContext.insert(newRecord)
            }

            try modelContext.save()
            await refreshAvailableLanguageIdentifiers()
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
            visibleRows = []
            availableLanguageIdentifiers = []
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

    func exportRows(filter: LearningWordFilter, searchText: String, sourceLanguageIdentifier: String? = nil) async -> [LearningExportRow] {
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let descriptor = FetchDescriptor<WordRecord>(
                predicate: listPredicate(
                    filter: filter,
                    searchText: query,
                    sourceLanguageIdentifier: Self.normalizedLanguageIdentifier(sourceLanguageIdentifier),
                    now: Date()
                ),
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
        await refreshAvailableLanguageIdentifiers()
        await reloadWords(
            filter: currentFilter,
            searchText: currentSearchText,
            sourceLanguageIdentifier: currentSourceLanguageIdentifier
        )
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
        sourceLanguageIdentifier: String?,
        now: Date
    ) -> Predicate<WordRecord>? {
        let query = searchText
        let language = sourceLanguageIdentifier

        switch (filter, query.isEmpty, language) {
        case (.all, true, nil):
            return nil
        case (.all, false, nil):
            return #Predicate { $0.word.contains(query) }
        case (.all, true, .some(let language)):
            return #Predicate { $0.sourceLanguageIdentifier == language }
        case (.all, false, .some(let language)):
            return #Predicate { $0.word.contains(query) && $0.sourceLanguageIdentifier == language }
        case (.pendingReview, true, nil):
            return pendingReviewPredicate(now: now)
        case (.pendingReview, false, nil):
            return #Predicate { record in
                if let nextReviewDate = record.nextReviewDate {
                    record.word.contains(query) && !record.isMastered && nextReviewDate <= now
                } else {
                    false
                }
            }
        case (.pendingReview, true, .some(let language)):
            return #Predicate { record in
                if let nextReviewDate = record.nextReviewDate {
                    record.sourceLanguageIdentifier == language && !record.isMastered && nextReviewDate <= now
                } else {
                    false
                }
            }
        case (.pendingReview, false, .some(let language)):
            return #Predicate { record in
                if let nextReviewDate = record.nextReviewDate {
                    record.word.contains(query) && record.sourceLanguageIdentifier == language && !record.isMastered && nextReviewDate <= now
                } else {
                    false
                }
            }
        case (.mastered, true, nil):
            return #Predicate { $0.isMastered }
        case (.mastered, false, nil):
            return #Predicate { $0.isMastered && $0.word.contains(query) }
        case (.mastered, true, .some(let language)):
            return #Predicate { $0.isMastered && $0.sourceLanguageIdentifier == language }
        case (.mastered, false, .some(let language)):
            return #Predicate { $0.isMastered && $0.word.contains(query) && $0.sourceLanguageIdentifier == language }
        }
    }

    private static func normalizedLanguageIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
