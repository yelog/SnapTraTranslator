import XCTest
@testable import SnapTra_Translator

@MainActor
final class LookupLanguagePairTests: XCTestCase {
    func testFixedLanguagePairPreservesIdentifiers() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "ja")

        XCTAssertEqual(pair.sourceIdentifier, "en")
        XCTAssertEqual(pair.targetIdentifier, "ja")
    }

    func testSameLanguageDetection() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "en")
        XCTAssertTrue(pair.isSameLanguage)
    }

    func testDifferentLanguageDetection() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")
        XCTAssertFalse(pair.isSameLanguage)
    }
}

@MainActor
final class SettingsStoreMigrationTests: XCTestCase {
    func testDefaultDictionarySourcesIncludeNewOnlineProviders() {
        let sources = SettingsStore.defaultDictionarySources(ecdictInstalled: false)

        XCTAssertEqual(
            sources.map(\.type),
            [.ecdict, .system, .google, .bing, .youdao, .deepl]
        )
        XCTAssertTrue(sources.contains { $0.type == .system && $0.isEnabled })
        XCTAssertTrue(sources.contains { $0.type == .google && !$0.isEnabled })
        XCTAssertTrue(sources.contains { $0.type == .bing && !$0.isEnabled })
        XCTAssertTrue(sources.contains { $0.type == .youdao && !$0.isEnabled })
        XCTAssertTrue(sources.contains { $0.type == .deepl && !$0.isEnabled })
    }

    func testMigrationAppendsOnlineProvidersWithoutChangingExistingOrder() {
        let existing: [DictionarySource] = [
            DictionarySource(id: UUID(), name: "System Dictionary", type: .system, isEnabled: true),
            DictionarySource(id: UUID(), name: "WordNet", type: .wordNet, isEnabled: false),
            DictionarySource(id: UUID(), name: "Advanced Dictionary", type: .ecdict, isEnabled: true),
        ]
        let migrated = SettingsStore.migrateDictionarySources(existing)

        XCTAssertEqual(
            migrated.map(\.type),
            [.system, .wordNet, .ecdict, .google, .bing, .youdao, .deepl]
        )
        XCTAssertEqual(
            migrated.filter(\.isEnabled).map(\.type),
            [.system, .ecdict]
        )
    }
}
