import SwiftData
import XCTest
@testable import SnapTra_Translator

@MainActor
final class LearningServicePaginationTests: XCTestCase {
    func testReloadLoadsFirstPageAndLoadMoreAppendsRemainingRecords() async throws {
        let context = try makeModelContext()
        try insertWords(count: 125, into: context)

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")

        XCTAssertEqual(service.visibleWords.count, 100)
        XCTAssertEqual(service.visibleRows.map(\.id), service.visibleWords.map(\.word))
        XCTAssertTrue(service.hasMoreWords)

        await service.loadMoreWords()

        XCTAssertEqual(service.visibleWords.count, 125)
        XCTAssertEqual(service.visibleRows.map(\.id), service.visibleWords.map(\.word))
        XCTAssertFalse(service.hasMoreWords)
    }

    func testLoadMoreCanAppendMultiplePages() async throws {
        let context = try makeModelContext()
        try insertWords(count: 275, into: context)

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")
        XCTAssertEqual(service.visibleWords.count, 100)
        XCTAssertTrue(service.hasMoreWords)

        await service.loadMoreWords()
        XCTAssertEqual(service.visibleWords.count, 200)
        XCTAssertEqual(service.visibleRows.count, 200)
        XCTAssertTrue(service.hasMoreWords)

        await service.loadMoreWords()
        XCTAssertEqual(service.visibleWords.count, 275)
        XCTAssertEqual(service.visibleRows.map(\.id), service.visibleWords.map(\.word))
        XCTAssertFalse(service.hasMoreWords)
    }

    func testLargeStoreStillLoadsOnlyTheFirstPageInitially() async throws {
        let context = try makeModelContext()
        try insertWords(count: 5_000, into: context)

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")

        XCTAssertEqual(service.visibleWords.count, 100)
        XCTAssertEqual(service.visibleRows.count, 100)
        XCTAssertTrue(service.hasMoreWords)
    }

    func testSearchFindsRecordOutsideInitialPage() async throws {
        let context = try makeModelContext()
        try insertWords(count: 100, into: context)
        let needle = WordRecord(word: "needle")
        needle.lookupCount = 0
        context.insert(needle)
        try context.save()

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "needle")

        XCTAssertEqual(service.visibleWords.map(\.word), ["needle"])
    }

    func testLoadMoreSkipsWhileAlreadyLoading() async throws {
        let context = try makeModelContext()
        try insertWords(count: 125, into: context)

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")
        service.isLoadingPage = true

        await service.loadMoreWords()

        XCTAssertEqual(service.visibleWords.count, 100)
        XCTAssertTrue(service.hasMoreWords)
    }

    func testDeleteReloadsRemainingWords() async throws {
        let context = try makeModelContext()
        try insertWords(count: 12, into: context)

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")
        let deletedWord = try XCTUnwrap(service.visibleWords.first)

        await service.deleteWord(deletedWord)

        XCTAssertEqual(service.visibleWords.count, 11)
        XCTAssertFalse(service.visibleWords.contains { $0.word == deletedWord.word })
    }

    func testSortsSameLookupCountByLastLookupDateDescending() async throws {
        let context = try makeModelContext()
        let older = WordRecord(word: "older")
        older.lookupCount = 3
        older.lastLookupDate = Date(timeIntervalSince1970: 100)
        context.insert(older)

        let newer = WordRecord(word: "newer")
        newer.lookupCount = 3
        newer.lastLookupDate = Date(timeIntervalSince1970: 200)
        context.insert(newer)

        try context.save()

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")

        XCTAssertEqual(service.visibleWords.map(\.word), ["newer", "older"])
    }

    func testSortUsesWordAsStableTieBreaker() async throws {
        let context = try makeModelContext()
        let sharedDate = Date(timeIntervalSince1970: 100)

        let zulu = WordRecord(word: "zulu")
        zulu.lookupCount = 3
        zulu.lastLookupDate = sharedDate
        context.insert(zulu)

        let alpha = WordRecord(word: "alpha")
        alpha.lookupCount = 3
        alpha.lastLookupDate = sharedDate
        context.insert(alpha)

        try context.save()

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")

        XCTAssertEqual(service.visibleWords.map(\.word), ["alpha", "zulu"])
    }

    func testExportIncludesAllMatchingRecordsBeyondVisiblePage() async throws {
        let context = try makeModelContext()
        try insertWords(count: 125, into: context)

        let service = LearningService(modelContext: context)
        await service.reloadWords(filter: .all, searchText: "")
        let exportRows = await service.exportRows(filter: .all, searchText: "")

        XCTAssertEqual(service.visibleWords.count, 100)
        XCTAssertEqual(exportRows.count, 125)
    }

    func testFiltersReturnExpectedRecords() async throws {
        let context = try makeModelContext()

        let mastered = WordRecord(word: "mastered")
        mastered.isMastered = true
        mastered.nextReviewDate = nil
        context.insert(mastered)

        let pending = WordRecord(word: "pending")
        pending.nextReviewDate = Date(timeIntervalSinceNow: -60)
        context.insert(pending)

        let future = WordRecord(word: "future")
        future.nextReviewDate = Date(timeIntervalSinceNow: 60 * 60 * 24)
        context.insert(future)

        try context.save()

        let service = LearningService(modelContext: context)

        await service.reloadWords(filter: .mastered, searchText: "")
        XCTAssertEqual(service.visibleWords.map(\.word), ["mastered"])

        await service.reloadWords(filter: .pendingReview, searchText: "")
        XCTAssertEqual(service.visibleWords.map(\.word), ["pending"])
    }

    func testRecordLookupStoresSourceLanguage() async throws {
        let context = try makeModelContext()
        let service = LearningService(modelContext: context)

        await service.recordLookup(word: "hello", sourceLanguageIdentifier: "en")
        await service.reloadWords(filter: .all, searchText: "")

        XCTAssertEqual(service.visibleWords.first?.sourceLanguageIdentifier, "en")
    }

    func testLanguageFilterReturnsMatchingRecords() async throws {
        let context = try makeModelContext()
        context.insert(WordRecord(word: "hello", sourceLanguageIdentifier: "en"))
        context.insert(WordRecord(word: "你好", sourceLanguageIdentifier: "zh-Hans"))
        context.insert(WordRecord(word: "legacy"))
        try context.save()

        let service = LearningService(modelContext: context)

        await service.reloadWords(filter: .all, searchText: "", sourceLanguageIdentifier: "zh-Hans")

        XCTAssertEqual(service.visibleWords.map(\.word), ["你好"])
    }

    func testAvailableLanguageIdentifiersExcludeLegacyUnknownRecords() async throws {
        let context = try makeModelContext()
        context.insert(WordRecord(word: "hello", sourceLanguageIdentifier: "en"))
        context.insert(WordRecord(word: "legacy"))
        try context.save()

        let service = LearningService(modelContext: context)
        await service.refreshAvailableLanguageIdentifiers()

        XCTAssertEqual(service.availableLanguageIdentifiers, ["en"])
    }

    func testRecordLookupDoesNotRefreshLanguageSnapshot() async throws {
        let context = try makeModelContext()
        context.insert(WordRecord(word: "hello", sourceLanguageIdentifier: "en"))
        try context.save()
        let service = LearningService(modelContext: context)
        await service.refreshAvailableLanguageIdentifiers()

        await service.recordLookup(word: "bonjour", sourceLanguageIdentifier: "fr")

        XCTAssertEqual(service.availableLanguageIdentifiers, ["en"])
    }

    func testExplicitLanguageRefreshSeesNewLookupLanguage() async throws {
        let context = try makeModelContext()
        let service = LearningService(modelContext: context)

        await service.recordLookup(word: "bonjour", sourceLanguageIdentifier: "fr")
        XCTAssertTrue(service.availableLanguageIdentifiers.isEmpty)

        await service.refreshAvailableLanguageIdentifiers()

        XCTAssertEqual(service.availableLanguageIdentifiers, ["fr"])
    }

    func testRecordLookupAtFiveThousandRecordsUpdatesOnlyTargetWord() async throws {
        let context = try makeModelContext()
        try insertWords(count: 5_000, into: context)
        let untouchedDescriptor = FetchDescriptor<WordRecord>(
            predicate: #Predicate { $0.word == "word-4999" }
        )
        let targetDescriptor = FetchDescriptor<WordRecord>(
            predicate: #Predicate { $0.word == "word-0" }
        )
        let untouched = try XCTUnwrap(context.fetch(untouchedDescriptor).first)
        let target = try XCTUnwrap(context.fetch(targetDescriptor).first)
        let originalCount = untouched.lookupCount
        let targetOriginalCount = target.lookupCount
        let service = LearningService(modelContext: context)

        await service.recordLookup(word: "word-0", sourceLanguageIdentifier: "en")

        XCTAssertEqual(untouched.lookupCount, originalCount)
        XCTAssertEqual(target.lookupCount, targetOriginalCount + 1)
        XCTAssertEqual(target.sourceLanguageIdentifier, "en")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WordRecord>()), 5_000)
    }

    func testRecordLookupPreservesExistingAndNewWordLanguageSemantics() async throws {
        let context = try makeModelContext()
        context.insert(WordRecord(word: "hello", sourceLanguageIdentifier: "fr"))
        try context.save()
        let service = LearningService(modelContext: context)

        await service.recordLookup(word: "hello", sourceLanguageIdentifier: "en")
        await service.recordLookup(word: "bonjour", sourceLanguageIdentifier: "fr")
        await service.reloadWords(filter: .all, searchText: "")

        let records = Dictionary(uniqueKeysWithValues: service.visibleWords.map { ($0.word, $0) })
        XCTAssertEqual(records["hello"]?.lookupCount, 2)
        XCTAssertEqual(records["hello"]?.sourceLanguageIdentifier, "en")
        XCTAssertEqual(records["bonjour"]?.lookupCount, 1)
        XCTAssertEqual(records["bonjour"]?.sourceLanguageIdentifier, "fr")
    }

    func testIdenticalDefinitionUpdateReportsUnchanged() async throws {
        let context = try makeModelContext()
        context.insert(WordRecord(word: "hello", definitionText: "greeting"))
        try context.save()
        let service = LearningService(modelContext: context)

        let result = await service.updateDefinition(
            word: "hello",
            definitionText: "  greeting  "
        )

        XCTAssertEqual(result, .unchanged)
    }

    func testDefinitionUpdateReportsInsertedUpdatedAndUnchanged() async throws {
        let context = try makeModelContext()
        let service = LearningService(modelContext: context)

        let inserted = await service.updateDefinition(word: "hello", definitionText: "greeting")
        let updated = await service.updateDefinition(word: "hello", definitionText: "salutation")
        let unchanged = await service.updateDefinition(word: "hello", definitionText: nil)

        XCTAssertEqual(inserted, .inserted)
        XCTAssertEqual(updated, .updated)
        XCTAssertEqual(unchanged, .unchanged)
        await service.reloadWords(filter: .all, searchText: "hello")
        XCTAssertEqual(service.visibleWords.first?.definitionText, "salutation")
    }

    func testWordRecordDefinitionMutationReportsNoOp() {
        let record = WordRecord(word: "hello", definitionText: "greeting")

        XCTAssertFalse(record.updateDefinition(nil))
        XCTAssertFalse(record.updateDefinition("  greeting  "))
        XCTAssertTrue(record.updateDefinition("salutation"))
        XCTAssertEqual(record.definitionText, "salutation")
    }

    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([WordRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func insertWords(count: Int, into context: ModelContext) throws {
        for index in 0..<count {
            let record = WordRecord(word: "word-\(index)")
            record.lookupCount = count - index
            context.insert(record)
        }
        try context.save()
    }
}
