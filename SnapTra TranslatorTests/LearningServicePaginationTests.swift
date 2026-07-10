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
