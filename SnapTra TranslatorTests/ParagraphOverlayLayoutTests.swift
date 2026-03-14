import XCTest
@testable import SnapTra_Translator

final class ParagraphOverlayLayoutTests: XCTestCase {
    func testResolveKeepsPanelBelowWhenBelowSideFitsNaturalHeight() {
        let result = ParagraphOverlayLayout.resolve(
            naturalPanelHeight: 240,
            spaceBelow: 520,
            spaceAbove: 180
        )

        XCTAssertEqual(result.placement, .below)
        XCTAssertEqual(
            result.maxPanelHeight,
            520 - ParagraphOverlayLayout.gap - ParagraphOverlayLayout.edgeInset,
            accuracy: 0.001
        )
    }

    func testResolveUsesAboveWhenOnlyAboveSideFitsNaturalHeight() {
        let result = ParagraphOverlayLayout.resolve(
            naturalPanelHeight: 240,
            spaceBelow: 180,
            spaceAbove: 520
        )

        XCTAssertEqual(result.placement, .above)
        XCTAssertEqual(
            result.maxPanelHeight,
            520 - ParagraphOverlayLayout.gap - ParagraphOverlayLayout.edgeInset,
            accuracy: 0.001
        )
    }

    func testResolveChoosesLargerSideWhenNeitherSideFitsNaturalHeight() {
        let result = ParagraphOverlayLayout.resolve(
            naturalPanelHeight: 640,
            spaceBelow: 420,
            spaceAbove: 300
        )

        XCTAssertEqual(result.placement, .below)
        XCTAssertEqual(
            result.maxPanelHeight,
            420 - ParagraphOverlayLayout.gap - ParagraphOverlayLayout.edgeInset,
            accuracy: 0.001
        )
    }

    func testAttributedBuilderUsesHangingIndentForListItems() throws {
        let attributedText = ParagraphTextAttributedStringBuilder.build(
            text: "• Unlimited multi-agent parallel execution",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            preferredLineHeight: 20
        )

        let style = try XCTUnwrap(
            attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )

        XCTAssertEqual(style.firstLineHeadIndent, 0, accuracy: 0.001)
        XCTAssertGreaterThan(style.headIndent, 0)
    }

    func testAttributedBuilderKeepsPlainParagraphZeroIndent() throws {
        let attributedText = ParagraphTextAttributedStringBuilder.build(
            text: "Visual interface combined with command-line power",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            preferredLineHeight: 20
        )

        let style = try XCTUnwrap(
            attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )

        XCTAssertEqual(style.firstLineHeadIndent, 0, accuracy: 0.001)
        XCTAssertEqual(style.headIndent, 0, accuracy: 0.001)
    }

    func testParagraphFontSizingUsesActualContainerWidth() {
        let sample = ParagraphFontSizingSample(
            text: "• Instant OCR translation - Captures screen region around cursor and detects the word closest to your pointer",
            weight: .medium
        )
        let measuredWidth = ParagraphFontSizing.maximumLineWidth(
            for: sample.text,
            font: .systemFont(ofSize: ParagraphFontSizing.baseFontSize, weight: sample.weight)
        )

        let narrowFontSize = ParagraphFontSizing.optimalFontSize(
            for: [sample],
            containerWidth: 520,
            horizontalPadding: 18
        )
        let wideFontSize = ParagraphFontSizing.optimalFontSize(
            for: [sample],
            containerWidth: measuredWidth * 2 + 36,
            horizontalPadding: 18
        )

        XCTAssertGreaterThan(wideFontSize, narrowFontSize)
        XCTAssertGreaterThan(wideFontSize, 20)
    }

    func testParagraphFontSizingUsesLongestReadyTranslationLine() {
        let original = ParagraphFontSizingSample(
            text: "Short source line",
            weight: .medium
        )
        let translation = ParagraphFontSizingSample(
            text: "Translated output becomes the limiting line because it is substantially longer than the source content",
            weight: .semibold
        )
        let translationWidth = ParagraphFontSizing.maximumLineWidth(
            for: translation.text,
            font: .systemFont(ofSize: ParagraphFontSizing.baseFontSize, weight: translation.weight)
        )
        let containerWidth = translationWidth + 36

        let originalOnlyFontSize = ParagraphFontSizing.optimalFontSize(
            for: [original],
            containerWidth: containerWidth,
            horizontalPadding: 18
        )
        let sharedFontSize = ParagraphFontSizing.optimalFontSize(
            for: [original, translation],
            containerWidth: containerWidth,
            horizontalPadding: 18
        )

        XCTAssertEqual(sharedFontSize, ParagraphFontSizing.baseFontSize, accuracy: 0.25)
        XCTAssertLessThan(sharedFontSize, originalOnlyFontSize)
    }
}
