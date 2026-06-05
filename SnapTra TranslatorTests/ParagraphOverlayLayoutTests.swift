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

    func testParagraphFontSizingAllowsLimitedUpsizingFromPreferredSize() {
        let fontSize = ParagraphFontSizing.optimalFontSize(
            preferredFontSize: 14,
            originalText: "Master Plan",
            containerWidth: 520,
            horizontalPadding: 18
        )

        XCTAssertEqual(
            fontSize,
            min(14 * ParagraphFontSizing.preferredUpscaleFactor, ParagraphFontSizing.maxFontSize),
            accuracy: 0.01
        )
    }

    func testParagraphFontSizingKeepsOriginalLongestLineWithinAvailableWidth() {
        let originalText = "This original line should cap the display size before it wraps in the panel"
        let targetFontSize = min(18 * ParagraphFontSizing.preferredUpscaleFactor, ParagraphFontSizing.maxFontSize)
        let targetWidth = ParagraphFontSizing.maximumLineWidth(
            for: originalText,
            font: .systemFont(ofSize: targetFontSize, weight: .medium)
        )
        let availableWidth = floor(targetWidth * 0.7)
        let containerWidth = availableWidth + 36

        let fontSize = ParagraphFontSizing.optimalFontSize(
            preferredFontSize: 18,
            originalText: originalText,
            containerWidth: containerWidth,
            horizontalPadding: 18
        )

        XCTAssertLessThan(fontSize, targetFontSize)

        let measuredWidth = ParagraphFontSizing.maximumLineWidth(
            for: originalText,
            font: .systemFont(ofSize: fontSize, weight: .medium)
        )
        XCTAssertLessThanOrEqual(measuredWidth, availableWidth + 0.5)
    }

    func testParagraphFontSizingIgnoresTranslationLengthWhenUpsizingOriginalText() {
        let shortOriginal = "Master Plan"
        let fontSize = ParagraphFontSizing.optimalFontSize(
            preferredFontSize: 14,
            originalText: shortOriginal,
            containerWidth: 520,
            horizontalPadding: 18
        )

        XCTAssertGreaterThan(fontSize, 14)
    }

    func testOutsideClickPolicyDismissesPinnedParagraphOverlayOutsideProtectedFrames() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isParagraphOverlayPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            overlayFrame: CGRect(x: 100, y: 100, width: 200, height: 120),
            highlightFrame: CGRect(x: 320, y: 100, width: 120, height: 40),
            activeParagraphRect: CGRect(x: 320, y: 100, width: 120, height: 40)
        )

        XCTAssertTrue(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsOverlayClicks() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 150, y: 150),
            isParagraphOverlayPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            overlayFrame: CGRect(x: 100, y: 100, width: 200, height: 120),
            highlightFrame: nil,
            activeParagraphRect: nil
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsParagraphRegionClicks() {
        let paragraphRect = CGRect(x: 320, y: 100, width: 120, height: 40)

        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 315, y: 118),
            isParagraphOverlayPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            overlayFrame: CGRect(x: 100, y: 100, width: 200, height: 120),
            highlightFrame: nil,
            activeParagraphRect: paragraphRect
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsHighlightWindowClicks() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 330, y: 118),
            isParagraphOverlayPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            overlayFrame: nil,
            highlightFrame: CGRect(x: 320, y: 100, width: 120, height: 40),
            activeParagraphRect: nil
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyDoesNotDismissWhileParagraphRegionIsInteractive() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isParagraphOverlayPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: true,
            overlayFrame: nil,
            highlightFrame: nil,
            activeParagraphRect: nil
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyOnlyDismissesPinnedParagraphOverlay() {
        XCTAssertFalse(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isParagraphOverlayPresented: false,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            overlayFrame: nil,
            highlightFrame: nil,
            activeParagraphRect: nil
        ))

        XCTAssertFalse(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isParagraphOverlayPresented: true,
            isParagraphOverlayPinned: false,
            isRegionInteractionActive: false,
            overlayFrame: nil,
            highlightFrame: nil,
            activeParagraphRect: nil
        ))
    }
}
