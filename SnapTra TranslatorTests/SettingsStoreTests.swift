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
    private let testKeys: [String] = [
        AppSettingKey.playPronunciation,
        AppSettingKey.playWordPronunciation,
        AppSettingKey.playSentencePronunciation,
        AppSettingKey.copyWord,
        AppSettingKey.copySentence,
        AppSettingKey.launchAtLogin,
        AppSettingKey.showMenuBarIcon,
        AppSettingKey.showDockIcon,
        AppSettingKey.singleKey,
        AppSettingKey.sourceLanguage,
        AppSettingKey.targetLanguage,
        AppSettingKey.debugShowOcrRegion,
        AppSettingKey.continuousTranslation,
        AppSettingKey.wordTTSProvider,
        AppSettingKey.sentenceTTSProvider,
        AppSettingKey.appLanguage,
        AppSettingKey.englishAccent,
        AppSettingKey.legacySentenceTranslationEnabled,
        AppSettingKey.ocrSentenceTranslationEnabled,
        AppSettingKey.selectedTextTranslationEnabled,
        AppSettingKey.autoCheckUpdates,
        AppSettingKey.updateChannel,
        AppSettingKey.debugShowChannelSelector,
        "dictionarySources",
        "sentenceTranslationSources",
    ]

    private func makeDefaults(testName: String = #function) -> UserDefaults {
        let defaults = UserDefaults.standard
        reset(defaults)
        return defaults
    }

    override func tearDown() {
        reset(.standard)
        super.tearDown()
    }

    private func reset(_ defaults: UserDefaults) {
        for key in testKeys {
            defaults.removeObject(forKey: key)
        }
    }

    func testDefaultDictionarySources() {
        let sources = SettingsStore.defaultDictionarySources(ecdictInstalled: false)

        XCTAssertEqual(
            sources.map(\.type),
            [.ecdict, .system, .youdao, .google, .freeDictionaryAPI]
        )
        XCTAssertTrue(sources.contains { $0.type == .system && $0.isEnabled })
        XCTAssertFalse(sources.contains { $0.type == .youdao && $0.isEnabled })
        XCTAssertFalse(sources.contains { $0.type == .google && $0.isEnabled })
        XCTAssertFalse(sources.contains { $0.type == .freeDictionaryAPI && $0.isEnabled })
    }

    func testMigrationPreservesSources() {
        let existing: [DictionarySource] = [
            DictionarySource(id: UUID(), name: "System Dictionary", type: .system, isEnabled: true),
            DictionarySource(id: UUID(), name: "Advanced Dictionary", type: .ecdict, isEnabled: false),
        ]
        let migrated = SettingsStore.migrateDictionarySources(existing)

        XCTAssertEqual(
            migrated.map(\.type),
            [.system, .ecdict, .youdao, .google, .freeDictionaryAPI]
        )
        XCTAssertTrue(migrated[0].isEnabled)
        XCTAssertFalse(migrated[1].isEnabled)
        XCTAssertFalse(migrated[2].isEnabled)
        XCTAssertFalse(migrated[3].isEnabled)
        XCTAssertFalse(migrated[4].isEnabled)
    }

    func testLegacySentenceTranslationSettingMigratesToOcrSentenceToggle() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: AppSettingKey.legacySentenceTranslationEnabled)

        let settings = SettingsStore.loadSentenceTranslationSettings(defaults: defaults)

        XCTAssertFalse(settings.ocrSentenceTranslationEnabled)
        XCTAssertEqual(
            defaults.object(forKey: AppSettingKey.ocrSentenceTranslationEnabled) as? Bool,
            false
        )
    }

    func testSelectedTextTranslationDefaultsToEnabled() {
        let defaults = makeDefaults()

        let settings = SettingsStore.loadSentenceTranslationSettings(defaults: defaults)

        XCTAssertTrue(settings.selectedTextTranslationEnabled)
    }
}

@MainActor
final class SelectedTextLookupRoutingTests: XCTestCase {
    func testInsideSelectionRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testSnapshotWithoutBoundsStillRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: nil,
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 260, y: 200),
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testMouseOutsideBoundsStillRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 260, y: 200),
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testMissingAccessibilityFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: false,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }

    func testDisabledSelectedTextFeatureFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationEnabled: false,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }
}

final class OnlineDictionaryServiceTests: XCTestCase {
    func testGoogleResponseParsesGroupedDefinitions() {
        let data = Data(
            #"""
            {
              "sentences": [{ "trans": "苹果", "orig": "apple" }],
              "dict": [
                {
                  "pos": "noun",
                  "terms": ["苹果", "苹"]
                }
              ],
              "definitions": [
                {
                  "pos": "noun",
                  "entry": [
                    {
                      "gloss": "the round fruit of a tree",
                      "definition_id": "def-1"
                    }
                  ]
                }
              ],
              "examples": {
                "example": [
                  {
                    "text": "an <b>apple</b> pie",
                    "definition_id": "def-1"
                  }
                ]
              }
            }
            """#.utf8
        )

        let entry = OnlineDictionaryService.parseGoogleResponse(data, word: "apple")

        XCTAssertEqual(entry?.source, .googleTranslate)
        XCTAssertEqual(entry?.definitions.count, 1)
        XCTAssertEqual(entry?.definitions.first?.partOfSpeech, "noun")
        XCTAssertEqual(entry?.definitions.first?.translation, "苹果；苹")
        XCTAssertEqual(entry?.definitions.first?.examples, ["an apple pie"])
        XCTAssertTrue(entry?.isPretranslated == true)
    }

    func testFreeDictionaryResponseParsesEnglishDefinitions() {
        let data = Data(
            #"""
            [
              {
                "word": "hello",
                "phonetics": [
                  { "text": "/həˈloʊ/" }
                ],
                "meanings": [
                  {
                    "partOfSpeech": "interjection",
                    "synonyms": ["greeting"],
                    "definitions": [
                      {
                        "definition": "A greeting.",
                        "example": "Hello, world!",
                        "synonyms": ["hi"]
                      }
                    ]
                  }
                ]
              }
            ]
            """#.utf8
        )

        let entry = OnlineDictionaryService.parseFreeDictionaryResponse(data, word: "hello")

        XCTAssertEqual(entry?.source, .freeDictionaryAPI)
        XCTAssertEqual(entry?.phonetic, "/həˈloʊ/")
        XCTAssertEqual(entry?.definitions.count, 1)
        XCTAssertEqual(entry?.definitions.first?.partOfSpeech, "interjection")
        XCTAssertEqual(entry?.definitions.first?.meaning, "A greeting.")
        XCTAssertNil(entry?.definitions.first?.translation)
        XCTAssertEqual(entry?.definitions.first?.examples, ["Hello, world!"])
        XCTAssertEqual(entry?.synonyms, ["greeting", "hi"])
        XCTAssertFalse(entry?.isPretranslated ?? true)
    }

    func testYoudaoHTMLParsesChineseGlossesAndPhonetics() {
        let html = #"""
        <div id="ec" class="trans-container ec ">
            <h2>
                <div>
                    <span>英<span class="phonetic">[wɜːd]</span></span>
                    <span>美<span class="phonetic">[wɜːrd]</span></span>
                </div>
            </h2>
            <ul>
                <li>n. 字，词，单词</li>
                <li>v. 措辞，用词</li>
            </ul>
        </div>
        """#

        let entry = OnlineDictionaryService.parseYoudaoHTML(html, word: "word")

        XCTAssertEqual(entry?.source, .youdaoDictionary)
        XCTAssertEqual(entry?.phonetic, "英 [wɜːd] 美 [wɜːrd]")
        XCTAssertEqual(entry?.definitions.count, 2)
        XCTAssertEqual(entry?.definitions.first?.partOfSpeech, "n")
        XCTAssertEqual(entry?.definitions.first?.translation, "字，词，单词")
        XCTAssertEqual(entry?.definitions.last?.partOfSpeech, "v")
        XCTAssertEqual(entry?.definitions.last?.translation, "措辞，用词")
        XCTAssertTrue(entry?.isPretranslated == true)
    }

    func testYoudaoHTMLParsesBracketedChinesePartOfSpeech() {
        let html = #"""
        <div id="ec" class="trans-container ec ">
            <ul>
                <li>【名】(Even)（美、挪）埃旺（人名）</li>
            </ul>
        </div>
        """#

        let entry = OnlineDictionaryService.parseYoudaoHTML(html, word: "even")

        XCTAssertEqual(entry?.definitions.count, 1)
        XCTAssertEqual(entry?.definitions.first?.partOfSpeech, "n")
        XCTAssertEqual(entry?.definitions.first?.translation, "(Even)（美、挪）埃旺（人名）")
    }
}
