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

    func testBidirectionalResolverKeepsConfiguredDirectionWhenDisabled() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")

        let result = LookupLanguagePairResolver.resolve(
            configuredPair: pair,
            observedText: "你好",
            bidirectionalEnabled: false
        )

        XCTAssertEqual(result, pair)
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
}
