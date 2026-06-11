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
        AppSettingKey.menuBarIconStyle,
        AppSettingKey.showDockIcon,
        AppSettingKey.singleKey,
        AppSettingKey.sourceLanguage,
        AppSettingKey.targetLanguage,
        AppSettingKey.bidirectionalTranslationEnabled,
        AppSettingKey.debugShowOcrRegion,
        AppSettingKey.continuousTranslation,
        AppSettingKey.keepWordOverlayAfterTap,
        AppSettingKey.wordTTSProvider,
        AppSettingKey.sentenceTTSProvider,
        AppSettingKey.appLanguage,
        AppSettingKey.englishAccent,
        AppSettingKey.legacySentenceTranslationEnabled,
        AppSettingKey.ocrSentenceTranslationEnabled,
        AppSettingKey.selectedTextTranslationEnabled,
        AppSettingKey.hideOriginalTextInSentenceOverlay,
        AppSettingKey.autoCheckUpdates,
        AppSettingKey.updateChannel,
        AppSettingKey.debugShowChannelSelector,
        "dictionarySources",
        "sentenceTranslationSources",
        "llmProviderConfigurations",
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

    func testSentenceTranslationSourceMigrationAppendsLLMProvidersDisabled() {
        let existing: [SentenceTranslationSource] = [
            SentenceTranslationSource(id: UUID(), type: .native, isEnabled: true),
            SentenceTranslationSource(id: UUID(), type: .google, isEnabled: true),
            SentenceTranslationSource(id: UUID(), type: .youdao, isEnabled: false),
        ]

        let migrated = SettingsStore.migrateSentenceTranslationSources(existing)

        XCTAssertEqual(migrated.prefix(3).map(\.type), [.native, .google, .youdao])
        XCTAssertTrue(migrated[0].isEnabled)
        XCTAssertTrue(migrated[1].isEnabled)
        XCTAssertFalse(migrated[2].isEnabled)
        XCTAssertEqual(
            migrated.filter { $0.type.isLLMProvider }.map(\.type),
            SentenceTranslationSource.SourceType.llmProviderTypes
        )
        XCTAssertTrue(migrated.filter { $0.type.isLLMProvider }.allSatisfy { !$0.isEnabled })
    }

    func testDefaultLLMProviderConfigurations() {
        let configurations = SettingsStore.defaultLLMProviderConfigurations()

        XCTAssertEqual(
            configurations.map(\.provider),
            SentenceTranslationSource.SourceType.llmProviderTypes
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .openAI }?.baseURL,
            "https://api.openai.com/v1"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .anthropic }?.model,
            "claude-haiku-4-5"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .gemini }?.model,
            "gemini-3.5-flash"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .deepSeek }?.model,
            "deepseek-v4-flash"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .zhipu }?.model,
            "glm-4.7-flash"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .zhipu }?.baseURL,
            "https://open.bigmodel.cn/api/paas/v4"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .zhipu }?.zhipuRegion,
            .domestic
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .ollama }?.baseURL,
            "http://localhost:11434/v1"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .omlx }?.baseURL,
            "http://localhost:8000/v1"
        )
    }

    func testLLMProviderConfigurationMigrationPreservesCustomValuesAndFillsMissingProviders() {
        let existing = [
            LLMProviderConfiguration(
                provider: .openAI,
                model: "custom-model",
                baseURL: "https://proxy.example/v1"
            ),
        ]

        let migrated = SettingsStore.migrateLLMProviderConfigurations(existing)

        XCTAssertEqual(
            migrated.map(\.provider),
            SentenceTranslationSource.SourceType.llmProviderTypes
        )
        XCTAssertEqual(migrated.first { $0.provider == .openAI }?.model, "custom-model")
        XCTAssertEqual(migrated.first { $0.provider == .openAI }?.baseURL, "https://proxy.example/v1")
        XCTAssertEqual(migrated.first { $0.provider == .gemini }?.baseURL, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertEqual(migrated.first { $0.provider == .zhipu }?.model, "glm-4.7-flash")
        XCTAssertEqual(migrated.first { $0.provider == .zhipu }?.baseURL, "https://open.bigmodel.cn/api/paas/v4")
        XCTAssertEqual(migrated.first { $0.provider == .zhipu }?.zhipuRegion, .domestic)
    }

    func testZhipuConfigurationInfersInternationalRegionFromBaseURL() {
        let existing = [
            LLMProviderConfiguration(
                provider: .zhipu,
                model: "glm-custom",
                baseURL: "https://api.z.ai/api/paas/v4"
            ),
        ]

        let migrated = SettingsStore.migrateLLMProviderConfigurations(existing)
        let zhipu = migrated.first { $0.provider == .zhipu }

        XCTAssertEqual(zhipu?.model, "glm-custom")
        XCTAssertEqual(zhipu?.baseURL, "https://api.z.ai/api/paas/v4")
        XCTAssertEqual(zhipu?.zhipuRegion, .international)
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

    func testBidirectionalTranslationDefaultsToEnabled() {
        let defaults = makeDefaults()

        let isEnabled = SettingsStore.loadBidirectionalTranslationEnabled(defaults: defaults)

        XCTAssertTrue(isEnabled)
    }

    func testMenuBarIconStyleDefaultsToAuto() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.menuBarIconStyle, .auto)
        XCTAssertEqual(defaults.string(forKey: AppSettingKey.menuBarIconStyle), MenuBarIconStyle.auto.rawValue)
    }

    func testLoadsPersistedMenuBarIconStyle() {
        let defaults = makeDefaults()
        defaults.set(MenuBarIconStyle.black.rawValue, forKey: AppSettingKey.menuBarIconStyle)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.menuBarIconStyle, .black)
    }

    func testLoadsPersistedBidirectionalTranslationSetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettingKey.bidirectionalTranslationEnabled)

        let isEnabled = SettingsStore.loadBidirectionalTranslationEnabled(defaults: defaults)
        XCTAssertTrue(isEnabled)
    }

    func testHideOriginalTextInSentenceOverlayDefaultsToEnabled() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.hideOriginalTextInSentenceOverlay)
        XCTAssertEqual(
            defaults.object(forKey: AppSettingKey.hideOriginalTextInSentenceOverlay) as? Bool,
            true
        )
    }

    func testLoadsPersistedHideOriginalTextInSentenceOverlaySetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettingKey.hideOriginalTextInSentenceOverlay)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.hideOriginalTextInSentenceOverlay)
    }

    func testKeepWordOverlayAfterTapDefaultsToDisabled() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertFalse(settings.keepWordOverlayAfterTap)
        XCTAssertEqual(
            defaults.object(forKey: AppSettingKey.keepWordOverlayAfterTap) as? Bool,
            false
        )
    }

    func testLoadsPersistedKeepWordOverlayAfterTapSetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettingKey.keepWordOverlayAfterTap)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.keepWordOverlayAfterTap)
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

    func testSnapshotWithoutBoundsRoutesToSelectedTextTranslation() {
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

    func testMouseOutsideBoundsRoutesToSelectedTextTranslation() {
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

    func testMouseNearSelectionEdgeRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 96, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testOversizedSelectionBoundsRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 1400, height: 700),
            sourceAppIdentifier: "com.microsoft.teams2"
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

    func testInvisibleSelectedTextFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "\u{200B}\u{FFFC}",
            selectedRange: NSRange(location: 0, length: 2),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.microsoft.teams2"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
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

final class LearningExportServiceTests: XCTestCase {
    private struct StubRecord: LearningExportRecord {
        var exportWord: String
        var exportSourceLanguageIdentifier: String?
        var exportDefinitionText: String?
        var exportLookupCount: Int
        var exportReviewStage: Int
        var exportIsMastered: Bool
    }

    func testExportRowCanBeBuiltFromRecord() {
        let record = StubRecord(
            exportWord: "apple",
            exportSourceLanguageIdentifier: "en",
            exportDefinitionText: "n. 苹果",
            exportLookupCount: 4,
            exportReviewStage: 2,
            exportIsMastered: false
        )

        let row = LearningExportRow(record: record)

        XCTAssertEqual(row.word, "apple")
        XCTAssertEqual(row.sourceLanguageName, "English")
        XCTAssertEqual(row.definitionText, "n. 苹果")
        XCTAssertEqual(row.lookupCount, 4)
        XCTAssertEqual(row.reviewStage, 2)
        XCTAssertFalse(row.isMastered)
    }

    func testAnkiTSVExportEscapesTabsAndNewlines() {
        let rows = [
            LearningExportRow(
                word: "hello",
                sourceLanguageName: "English",
                definitionText: "int. 你好\nused as a greeting\twith tab",
                lookupCount: 3,
                reviewStage: 1,
                isMastered: false
            ),
        ]

        let output = LearningExportService.export(rows: rows, format: .ankiTSV)

        XCTAssertEqual(
            output,
            "Word\tLanguage\tDefinition\tLookup Count\tReview Stage\tMastered\nhello\tEnglish\tint. 你好<br>used as a greeting with tab\t3\t1\tfalse\n"
        )
    }

    func testPlainTextExportWritesOneWordPerLine() {
        let rows = [
            LearningExportRow(
                word: "apple",
                sourceLanguageName: "English",
                definitionText: "n. apple",
                lookupCount: 3,
                reviewStage: 1,
                isMastered: false
            ),
            LearningExportRow(
                word: "banana",
                sourceLanguageName: "English",
                definitionText: "n. banana",
                lookupCount: 1,
                reviewStage: 0,
                isMastered: false
            ),
        ]

        let output = LearningExportService.export(rows: rows, format: .plainText)

        XCTAssertEqual(output, "apple\nbanana\n")
    }

    func testCSVExportQuotesCommaQuoteAndNewline() {
        let rows = [
            LearningExportRow(
                word: "quote",
                sourceLanguageName: "English",
                definitionText: "say, \"hello\"\nagain",
                lookupCount: 2,
                reviewStage: 0,
                isMastered: true
            ),
        ]

        let output = LearningExportService.export(rows: rows, format: .csv)

        XCTAssertEqual(
            output,
            "Word,Language,Definition,Lookup Count,Review Stage,Mastered\nquote,English,\"say, \"\"hello\"\"\nagain\",2,0,true\n"
        )
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

    func testChineseSystemDictionaryPlainTextStripsHeadwordPinyinAndPartOfSpeech() {
        let html = "服务器 fúwùqì 名 电子计算机网络中为用户提供服务的专用设备。可分为访问、文件、数据库、通信等不同功能的服务器。"

        let entry = DictionaryService.parseSystemDictionaryHTML(
            html,
            word: "服务器",
            sourceLanguage: "zh-Hans",
            targetLanguage: "en"
        )

        XCTAssertEqual(entry.definitions.count, 1)
        XCTAssertEqual(entry.definitions.first?.partOfSpeech, "n.")
        XCTAssertEqual(
            entry.definitions.first?.meaning,
            "电子计算机网络中为用户提供服务的专用设备。可分为访问、文件、数据库、通信等不同功能的服务器。"
        )
        XCTAssertNil(entry.definitions.first?.translation)
    }

    func testSystemDictionaryChineseTranslationStripsInlinePinyinSequences() {
        let html = "pull | BrE pʊl, AmE pʊl | A. transitive verb ① (tug) 拉 lā▸ ⑤ informal (complete successfully) 进行…得逞 jìnxíng… déchěng ‹raid, burglary›▸ ⑥ (steer) 使…转向 shǐ… zhuǎnxiàng ‹vehicle›▸ pull through 挺过来 tǐng guolai"

        let entry = DictionaryService.parseSystemDictionaryHTML(
            html,
            word: "pull",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        XCTAssertEqual(
            entry.definitions.map(\.translation),
            ["拉", "进行…得逞", "使…转向"]
        )
    }

    func testSystemDictionaryChineseTranslationPreservesEmbeddedEnglishWords() {
        let html = "pull | BrE pʊl, AmE pʊl | A. transitive verb ① (criticize) 抨击 pēngjī ; 诋毁 dǐhuǐ pull away intransitive verb▸ ② (computer) Mac 电脑; Apple Inc. 产品"

        let entry = DictionaryService.parseSystemDictionaryHTML(
            html,
            word: "pull",
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )

        XCTAssertEqual(
            entry.definitions.map(\.translation),
            ["抨击; 诋毁 pull away intransitive verb", "Mac 电脑; Apple Inc. 产品"]
        )
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
