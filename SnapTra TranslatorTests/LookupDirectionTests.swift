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
            observedText: "hello你好",
            bidirectionalEnabled: true
        )

        XCTAssertEqual(result, pair)
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
