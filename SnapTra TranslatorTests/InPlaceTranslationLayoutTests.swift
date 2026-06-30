import XCTest
@testable import SnapTra_Translator

final class InPlaceTranslationLayoutTests: XCTestCase {
    func testResolveKeepsSmallLineReadableAndInsideHeight() {
        let result = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 180, height: 24),
            preferredFontSize: 18,
            translatedText: "短句翻译"
        )

        XCTAssertEqual(result.padding, 4)
        XCTAssertEqual(result.cornerRadius, 4)
        XCTAssertLessThanOrEqual(result.fontSize, 24 * 0.48)
        XCTAssertGreaterThanOrEqual(result.fontSize, 10)
    }

    func testResolveReducesFontForLongTranslations() {
        let short = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 420, height: 90),
            preferredFontSize: 18,
            translatedText: "短句翻译"
        )
        let long = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 420, height: 90),
            preferredFontSize: 18,
            translatedText: String(repeating: "这是一段较长的翻译内容", count: 8)
        )

        XCTAssertLessThan(long.fontSize, short.fontSize)
    }

    func testResolveCapsLargeTextAtMaximumFontSize() {
        let result = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 800, height: 300),
            preferredFontSize: 40,
            translatedText: "Large translation"
        )

        XCTAssertEqual(result.fontSize, 22)
        XCTAssertEqual(result.padding, 8)
        XCTAssertEqual(result.cornerRadius, 7)
    }
}
