import XCTest
@testable import SnapTra_Translator

final class OCRTokenClassifierTests: XCTestCase {
    func testClassifiesEnglishToken() {
        let result = OCRTokenClassifier.classify("hello")
        XCTAssertEqual(result, .english)
    }

    func testClassifiesChineseToken() {
        let result = OCRTokenClassifier.classify("你好")
        XCTAssertEqual(result, .chinese)
    }

    func testClassifiesNumericTokenAsUnknown() {
        let result = OCRTokenClassifier.classify("2026")
        XCTAssertEqual(result, .unknown)
    }

    func testClassifiesMixedToken() {
        let result = OCRTokenClassifier.classify("hello你好")
        XCTAssertEqual(result, .mixed)
    }

    func testDirectionalPairSwitchesSourceWhenTargetingOriginalSource() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = pair.directionalPair(targeting: "en")

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "en")
        )
    }

    func testDirectionalPairKeepsDirectionWhenTargetingOriginalTarget() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = pair.directionalPair(targeting: "zh-Hans")

        XCTAssertEqual(result, pair)
    }

    func testBidirectionalResolverKeepsConfiguredDirectionWhenDisabled() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "你好",
            bidirectionalEnabled: false
        )

        XCTAssertEqual(result, pair)
    }

    func testLookupIsSkippedForTargetLanguageWhenBidirectionalDisabled() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.shouldLookup(
            configuredPair: pair,
            observedText: "你好",
            bidirectionalEnabled: false
        )

        XCTAssertFalse(result)
    }

    func testLookupContinuesForSourceLanguageWhenBidirectionalDisabled() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.shouldLookup(
            configuredPair: pair,
            observedText: "hello",
            bidirectionalEnabled: false
        )

        XCTAssertTrue(result)
    }

    func testLookupContinuesForTargetLanguageWhenBidirectionalEnabled() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.shouldLookup(
            configuredPair: pair,
            observedText: "你好",
            bidirectionalEnabled: true
        )

        XCTAssertTrue(result)
    }

    func testBidirectionalResolverUsesForwardDirectionForSourceText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "hello",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }

    func testBidirectionalResolverReversesDirectionForTargetText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "你好",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "en")
        )
    }

    func testBidirectionalResolverFallsBackForMixedText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "ab你好",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }

    func testBidirectionalResolverReversesDirectionForChineseDominantMixedText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "虽然我也承认 Kimi 2.6 不错，但这句主要是中文。",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "en")
        )
    }

    func testBidirectionalResolverKeepsForwardDirectionForEnglishDominantMixedText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "This feature supports 中文 labels in the sidebar",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }

    func testBidirectionalResolverIgnoresMentionAndURLNoise() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "@sailfishcc1 这是中文 https://example.com/post/123",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "en")
        )
    }

    func testBidirectionalResolverReversesDirectionForChineseSentenceWithEnglishTerms() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "还没正式开始用。 后面想尝试下 vibe coding。 好奇大家是直接使用 codex 桌面客户端还是使用 codex cli 进行编程的啊",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "en")
        )
    }

    func testBidirectionalResolverFallsBackForUnsupportedPair() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "ja")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "hello",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }

    func testManualImageTranslationDirectionReversesForTargetLanguageText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = ImageSentenceTranslationLanguagePairResolver.resolveManualRegionPair(
            recognizedText: "这是手动框选出来的中文图片区域",
            configuredPair: pair,
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "en")
        )
    }

    func testManualImageTranslationDirectionFallsBackWhenOCRTextIsEmpty() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = ImageSentenceTranslationLanguagePairResolver.resolveManualRegionPair(
            recognizedText: "",
            configuredPair: pair,
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }

    // MARK: - Russian ↔ Chinese Bidirectional Tests

    func testBidirectionalResolverReversesRussianChineseForChineseText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ru", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "物品",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "ru")
        )
    }

    func testBidirectionalResolverKeepsRussianChineseForCyrillicText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ru", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "привет",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }

    func testBidirectionalResolverReversesChineseRussianForCyrillicText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "ru")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "привет",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "ru", targetIdentifier: "zh-Hans")
        )
    }

    func testSupportsBidirectionalDetectionForRussianChinese() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ru", targetIdentifier: "zh-Hans")
        XCTAssertTrue(LookupLanguagePairResolver.supportsBidirectionalDetection(for: pair))
    }

    func testSupportsBidirectionalDetectionForEnglishChinese() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")
        XCTAssertTrue(LookupLanguagePairResolver.supportsBidirectionalDetection(for: pair))
    }

    func testSupportsBidirectionalDetectionReturnsFalseForSameScript() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "fr")
        XCTAssertFalse(LookupLanguagePairResolver.supportsBidirectionalDetection(for: pair))
    }

    // MARK: - Script Family Detection Tests

    func testScriptFamilyForEnglish() {
        XCTAssertEqual(LookupLanguagePairResolver.scriptFamily(for: "en"), "Latn")
    }

    func testScriptFamilyForRussian() {
        XCTAssertEqual(LookupLanguagePairResolver.scriptFamily(for: "ru"), "Cyrl")
    }

    func testScriptFamilyForChineseSimplified() {
        XCTAssertEqual(LookupLanguagePairResolver.scriptFamily(for: "zh-Hans"), "Hans")
    }

    func testScriptFamilyForChineseTraditional() {
        XCTAssertEqual(LookupLanguagePairResolver.scriptFamily(for: "zh-Hant"), "Hant")
    }

    func testScriptFamilyForJapanese() {
        XCTAssertEqual(LookupLanguagePairResolver.scriptFamily(for: "ja"), "Jpan")
    }

    func testScriptFamilyForKorean() {
        XCTAssertEqual(LookupLanguagePairResolver.scriptFamily(for: "ko"), "Kore")
    }

    func testObservedScriptFamilyForChinese() {
        XCTAssertEqual(LookupLanguagePairResolver.observedScriptFamily(for: "物品"), "Hans")
    }

    func testObservedScriptFamilyForCyrillic() {
        XCTAssertEqual(LookupLanguagePairResolver.observedScriptFamily(for: "привет"), "Cyrl")
    }

    func testObservedScriptFamilyForLatin() {
        XCTAssertEqual(LookupLanguagePairResolver.observedScriptFamily(for: "hello"), "Latn")
    }

    // MARK: - Japanese ↔ Chinese Bidirectional Tests

    func testBidirectionalResolverReversesJapaneseChineseForChineseText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ja", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "物品",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "ja")
        )
    }

    func testBidirectionalResolverKeepsJapaneseChineseForKanaText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ja", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "こんにちは",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }

    // MARK: - Korean ↔ Chinese Bidirectional Tests

    func testBidirectionalResolverReversesKoreanChineseForChineseText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ko", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "物品",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(
            result,
            LookupLanguagePair.fixed(sourceIdentifier: "zh-Hans", targetIdentifier: "ko")
        )
    }

    func testBidirectionalResolverKeepsKoreanChineseForHangulText() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ko", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "안녕하세요",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
    }
}

final class OverlayPrimaryTranslationStateTests: XCTestCase {
    func testDictionaryUpdateKeepsPrimaryTranslationLoadingWhileNativeTranslationPending() {
        let sections = [
            OverlayDictionarySection(
                sourceType: .system,
                state: .ready(Self.dictionaryEntry(translation: "管理者"))
            ),
        ]

        let state = AppModel.primaryTranslationStateAfterDictionaryUpdate(
            currentState: .loading,
            dictionarySections: sections
        )

        XCTAssertEqual(state, .loading)
    }

    func testFailedPrimaryTranslationUsesDictionaryFallback() {
        let sections = [
            OverlayDictionarySection(
                sourceType: .system,
                state: .ready(Self.dictionaryEntry(translation: "管理者"))
            ),
        ]

        let state = AppModel.primaryTranslationStateAfterPrimaryTranslationUpdate(
            incomingState: .failed("Translation failed"),
            currentState: .loading,
            dictionarySections: sections
        )

        XCTAssertEqual(state, .ready("管理者", isFallback: true))
    }

    func testReadyPrimaryTranslationReplacesDictionaryFallback() {
        let sections = [
            OverlayDictionarySection(
                sourceType: .system,
                state: .ready(Self.dictionaryEntry(translation: "管理者"))
            ),
        ]

        let state = AppModel.primaryTranslationStateAfterPrimaryTranslationUpdate(
            incomingState: .ready("管理员", isFallback: false),
            currentState: .ready("管理者", isFallback: true),
            dictionarySections: sections
        )

        XCTAssertEqual(state, .ready("管理员", isFallback: false))
    }

    private static func dictionaryEntry(translation: String) -> DictionaryEntry {
        DictionaryEntry(
            word: "Administrator",
            phonetic: nil,
            definitions: [
                DictionaryEntry.Definition(
                    partOfSpeech: "n.",
                    field: nil,
                    meaning: "a person responsible for running a business",
                    translation: translation,
                    examples: []
                ),
            ],
            source: .systemDictionary,
            synonyms: []
        )
    }
}

final class OverlayDictionarySectionDisplayTests: XCTestCase {
    func testChineseSourceHidesEmptySystemDictionarySection() {
        let content = OverlayContent(
            word: "权限",
            phonetic: nil,
            primaryTranslationState: .ready("permission", isFallback: false),
            usesCompactPrimaryTranslationStyle: true,
            dictionarySections: [
                OverlayDictionarySection(sourceType: .system, state: .empty),
            ],
            sourceLanguageIdentifier: "zh-Hans"
        )

        XCTAssertTrue(content.visibleDictionarySections.isEmpty)
    }

    func testChineseSourceKeepsReadySystemDictionarySection() {
        let content = OverlayContent(
            word: "权限",
            phonetic: nil,
            primaryTranslationState: .ready("permission", isFallback: false),
            usesCompactPrimaryTranslationStyle: true,
            dictionarySections: [
                OverlayDictionarySection(
                    sourceType: .system,
                    state: .ready(Self.dictionaryEntry(translation: "permission"))
                ),
            ],
            sourceLanguageIdentifier: "zh-Hans"
        )

        XCTAssertEqual(content.visibleDictionarySections.count, 1)
    }

    func testEnglishSourceKeepsEmptySystemDictionarySection() {
        let content = OverlayContent(
            word: "permission",
            phonetic: nil,
            primaryTranslationState: .ready("权限", isFallback: false),
            usesCompactPrimaryTranslationStyle: true,
            dictionarySections: [
                OverlayDictionarySection(sourceType: .system, state: .empty),
            ],
            sourceLanguageIdentifier: "en"
        )

        XCTAssertEqual(content.visibleDictionarySections.count, 1)
    }

    private static func dictionaryEntry(translation: String) -> DictionaryEntry {
        DictionaryEntry(
            word: "权限",
            phonetic: nil,
            definitions: [
                .init(
                    partOfSpeech: "",
                    field: nil,
                    meaning: translation,
                    translation: translation,
                    examples: []
                ),
            ],
            source: .systemDictionary,
            synonyms: []
        )
    }
}
