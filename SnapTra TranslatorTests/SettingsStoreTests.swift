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
        AppSettingKey.bidirectionalTranslationEnabled,
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
        let suiteName = "SettingsStoreMigrationTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
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
            [.system, .ecdict, .youdao, .google, .freeDictionaryAPI]
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

    func testBidirectionalTranslationDefaultsToDisabled() {
        let defaults = makeDefaults()

        let isEnabled = SettingsStore.loadBidirectionalTranslationEnabled(defaults: defaults)

        XCTAssertFalse(isEnabled)
    }

    func testLoadsPersistedBidirectionalTranslationSetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettingKey.bidirectionalTranslationEnabled)

        let isEnabled = SettingsStore.loadBidirectionalTranslationEnabled(defaults: defaults)
        XCTAssertTrue(isEnabled)
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
            isSelectedTextTranslationSupported: true,
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
            isSelectedTextTranslationSupported: true,
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
            isSelectedTextTranslationSupported: true,
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
            isSelectedTextTranslationSupported: true,
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
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: false,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }

    func testUnsupportedSelectedTextCapabilityFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: false,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }
}

final class OnlineDictionaryServiceTests: XCTestCase {
    func testGoogleResponseErrorDetectsBlockedHtmlPage() {
        let html = #"""
        <html>
        <body>
        Our systems have detected unusual traffic from your computer network.
        Please try your request again later.
        </body>
        </html>
        """#

        let error = OnlineDictionaryService.googleResponseError(
            data: Data(html.utf8),
            mimeType: "text/html"
        )

        XCTAssertEqual(error, .blockedByGoogle)
    }

    func testGoogleResponseErrorIgnoresJsonPayload() {
        let data = Data(
            #"""
            {
              "sentences": [{ "trans": "host" }]
            }
            """#.utf8
        )

        let error = OnlineDictionaryService.googleResponseError(
            data: data,
            mimeType: "application/json"
        )

        XCTAssertNil(error)
    }

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

final class DictionaryLookupSupportTests: XCTestCase {
    func testSystemDictionarySupportsChineseToEnglishReverseLookup() {
        XCTAssertTrue(
            DictionarySource.SourceType.system.supportsLookup(
                sourceIdentifier: "zh-Hans",
                targetIdentifier: "en"
            )
        )
    }

    func testGoogleSupportsChineseToEnglishReverseLookup() {
        XCTAssertTrue(
            DictionarySource.SourceType.google.supportsLookup(
                sourceIdentifier: "zh-Hans",
                targetIdentifier: "en"
            )
        )
    }

    func testEnglishOnlySourcesDoNotSupportChineseToEnglishReverseLookup() {
        XCTAssertFalse(
            DictionarySource.SourceType.ecdict.supportsLookup(
                sourceIdentifier: "zh-Hans",
                targetIdentifier: "en"
            )
        )
        XCTAssertFalse(
            DictionarySource.SourceType.freeDictionaryAPI.supportsLookup(
                sourceIdentifier: "zh-Hans",
                targetIdentifier: "en"
            )
        )
        XCTAssertFalse(
            DictionarySource.SourceType.youdao.supportsLookup(
                sourceIdentifier: "zh-Hans",
                targetIdentifier: "en"
            )
        )
    }
}

final class DictionaryServiceSystemParserTests: XCTestCase {
    func testChineseHeadwordUsesGeneralSystemDictionaryParserDuringReverseLookup() {
        let html = #"""
        <span class="posg">名词</span>
        ① experience 体验
        """#

        let entry = DictionaryService.parseSystemDictionaryHTML(
            html,
            word: "体验",
            sourceLanguage: "zh-Hans",
            targetLanguage: "en"
        )

        XCTAssertEqual(entry.definitions.count, 1)
        XCTAssertEqual(entry.definitions.first?.partOfSpeech, "n.")
        XCTAssertEqual(entry.definitions.first?.meaning, "experience")
        XCTAssertEqual(entry.definitions.first?.translation, "体验")
    }
}

final class DictionaryDefinitionTranslationDecisionTests: XCTestCase {
    func testEnglishFastPathAllowsEnglishSourceDefinitions() {
        let definition = DictionaryEntry.Definition(
            partOfSpeech: "v.",
            field: nil,
            meaning: "to deploy software to a target environment",
            translation: nil,
            examples: []
        )

        let translation = AppModel.englishFastPathTranslation(
            for: definition,
            sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "en")
        )

        XCTAssertEqual(translation, "to deploy software to a target environment")
    }

    func testEnglishFastPathRejectsChineseSourceDefinitionsContainingPinyin() {
        let definition = DictionaryEntry.Definition(
            partOfSpeech: "v.",
            field: nil,
            meaning: "配置 peizhi 动配备并设置",
            translation: nil,
            examples: []
        )

        let translation = AppModel.englishFastPathTranslation(
            for: definition,
            sourceLanguage: Locale.Language(identifier: "zh-Hans"),
            targetLanguage: Locale.Language(identifier: "en")
        )

        XCTAssertNil(translation)
    }
}
