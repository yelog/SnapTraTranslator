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

    func testResolveAlignsTextFrameToFirstSourceLine() {
        let sourceRect = CGRect(x: 100, y: 200, width: 300, height: 120)
        let result = InPlaceTranslationLayout.resolve(
            sourceRect: sourceRect,
            sourceLineRects: [CGRect(x: 130, y: 230, width: 180, height: 24)],
            preferredFontSize: 18,
            translatedText: "需要软件更新"
        )

        XCTAssertGreaterThanOrEqual(result.textFrame.origin.x, 30)
        XCTAssertGreaterThanOrEqual(result.textFrame.origin.y, 30)
        XCTAssertLessThan(result.textFrame.origin.x, 40)
        XCTAssertLessThan(result.textFrame.origin.y, 40)
        XCTAssertGreaterThan(result.textFrame.size.width, 240)
        XCTAssertGreaterThan(result.textFrame.size.height, 70)
    }

    func testResolveFallsBackToTopLeadingWhenLineRectsAreEmpty() {
        let result = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 220, height: 80),
            sourceLineRects: [],
            preferredFontSize: 16,
            translatedText: "Fallback"
        )

        XCTAssertGreaterThanOrEqual(result.textFrame.origin.x, 2)
        XCTAssertGreaterThanOrEqual(result.textFrame.origin.y, 2)
        XCTAssertGreaterThan(result.textFrame.size.width, 180)
        XCTAssertGreaterThan(result.textFrame.size.height, 50)
    }

    func testResolveKeepsTextFrameInsideSourceBounds() {
        let result = InPlaceTranslationLayout.resolve(
            sourceRect: CGRect(x: 100, y: 100, width: 140, height: 40),
            sourceLineRects: [CGRect(x: 230, y: 135, width: 200, height: 20)],
            preferredFontSize: 16,
            translatedText: "Long translated text"
        )

        XCTAssertGreaterThanOrEqual(result.textFrame.origin.x, 0)
        XCTAssertGreaterThanOrEqual(result.textFrame.origin.y, 0)
        XCTAssertLessThanOrEqual(result.textFrame.origin.x + result.textFrame.size.width, 140)
        XCTAssertLessThanOrEqual(result.textFrame.origin.y + result.textFrame.size.height, 40)
    }
}
