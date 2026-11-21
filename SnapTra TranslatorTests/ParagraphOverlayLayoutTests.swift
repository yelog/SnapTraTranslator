import SwiftUI
import XCTest
@testable import SnapTra_Translator

final class ParagraphOverlayLayoutTests: XCTestCase {
    func testManualRegionSelectionPresentationKeepsBrowserFocusAndAcceptsInitialClick() {
        XCTAssertFalse(ManualRegionSelectionPresentationPolicy.activatesApplication)
        XCTAssertTrue(ManualRegionSelectionPresentationPolicy.acceptsFirstMouse)
    }

    func testParagraphHighlightResizeGeometryUsesStableScreenDeltaForAllCorners() {
        let startFrame = CGRect(x: 100, y: 200, width: 240, height: 80)
        let minimumSize = CGSize(width: 80, height: 24)
        let screenFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let delta = CGSize(width: 30, height: 20)

        XCTAssertEqual(
            ParagraphHighlightResizeGeometry.resizedFrame(
                from: startFrame,
                corner: .topLeft,
                screenDelta: delta,
                minimumSize: minimumSize,
                screenFrame: screenFrame
            ),
            CGRect(x: 130, y: 200, width: 210, height: 100)
        )
        XCTAssertEqual(
            ParagraphHighlightResizeGeometry.resizedFrame(
                from: startFrame,
                corner: .topRight,
                screenDelta: delta,
                minimumSize: minimumSize,
                screenFrame: screenFrame
            ),
            CGRect(x: 100, y: 200, width: 270, height: 100)
        )
        XCTAssertEqual(
            ParagraphHighlightResizeGeometry.resizedFrame(
                from: startFrame,
                corner: .bottomLeft,
                screenDelta: delta,
                minimumSize: minimumSize,
                screenFrame: screenFrame
            ),
            CGRect(x: 130, y: 220, width: 210, height: 60)
        )
        XCTAssertEqual(
            ParagraphHighlightResizeGeometry.resizedFrame(
                from: startFrame,
                corner: .bottomRight,
                screenDelta: delta,
                minimumSize: minimumSize,
                screenFrame: screenFrame
            ),
            CGRect(x: 100, y: 220, width: 270, height: 60)
        )
    }

    func testParagraphHighlightResizeGeometryPreservesOppositeCornerAtMinimumSize() {
        let startFrame = CGRect(x: 100, y: 200, width: 120, height: 60)
        let minimumSize = CGSize(width: 80, height: 24)
        let screenFrame = CGRect(x: 0, y: 0, width: 800, height: 600)

        let frame = ParagraphHighlightResizeGeometry.resizedFrame(
            from: startFrame,
            corner: .topLeft,
            screenDelta: CGSize(width: 100, height: 100),
            minimumSize: minimumSize,
            screenFrame: screenFrame
        )

        XCTAssertEqual(frame, CGRect(x: 140, y: 200, width: 80, height: 160))
    }

    func testParagraphHighlightCornerFeedbackStrengthensHoverAffordance() {
        let normal = ParagraphHighlightCornerFeedback.resolve(
            corner: .topLeft,
            hoveredCorner: nil,
            activeCorner: nil
        )
        let hovered = ParagraphHighlightCornerFeedback.resolve(
            corner: .topLeft,
            hoveredCorner: .topLeft,
            activeCorner: nil
        )

        XCTAssertEqual(normal.lineWidth, 2.5, accuracy: 0.001)
        XCTAssertFalse(normal.showsGrip)
        XCTAssertEqual(hovered.lineWidth, 3.5, accuracy: 0.001)
        XCTAssertTrue(hovered.showsGrip)
        XCTAssertGreaterThan(hovered.opacity, normal.opacity)
    }

    func testParagraphHighlightCornerFeedbackKeepsDraggingCornerProminent() {
        let feedback = ParagraphHighlightCornerFeedback.resolve(
            corner: .topLeft,
            hoveredCorner: .bottomRight,
            activeCorner: .topLeft
        )

        XCTAssertEqual(feedback.lineWidth, 4, accuracy: 0.001)
        XCTAssertEqual(feedback.gripDiameter, 7, accuracy: 0.001)
        XCTAssertTrue(feedback.showsGrip)
    }

    func testParagraphHighlightResizeHitTestingResolvesAllCornerHoverPoints() {
        let size = CGSize(width: 240, height: 80)
        let handleSize: CGFloat = 36

        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 1, y: 1),
                in: size,
                handleSize: handleSize
            ),
            .topLeft
        )
        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 239, y: 1),
                in: size,
                handleSize: handleSize
            ),
            .topRight
        )
        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 1, y: 79),
                in: size,
                handleSize: handleSize
            ),
            .bottomLeft
        )
        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 239, y: 79),
                in: size,
                handleSize: handleSize
            ),
            .bottomRight
        )
        XCTAssertNil(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 120, y: 40),
                in: size,
                handleSize: handleSize
            )
        )
    }

    func testParagraphHighlightResizeHitTestingClampsCornerRectsInsideOverlay() {
        let size = CGSize(width: 240, height: 80)
        let handleSize: CGFloat = 36

        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.handleRect(
                for: .topLeft,
                in: size,
                handleSize: handleSize
            ),
            CGRect(x: 0, y: 0, width: 36, height: 36)
        )
        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.handleRect(
                for: .bottomRight,
                in: size,
                handleSize: handleSize
            ),
            CGRect(x: 204, y: 44, width: 36, height: 36)
        )
    }

    func testParagraphHighlightResizeHitTestingChoosesNearestCornerWhenHotZonesOverlap() {
        let size = CGSize(width: 80, height: 24)
        let handleSize: CGFloat = 36

        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 1, y: 1),
                in: size,
                handleSize: handleSize
            ),
            .topLeft
        )
        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 1, y: 23),
                in: size,
                handleSize: handleSize
            ),
            .bottomLeft
        )
        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 79, y: 1),
                in: size,
                handleSize: handleSize
            ),
            .topRight
        )
        XCTAssertEqual(
            ParagraphHighlightResizeHitTesting.corner(
                at: CGPoint(x: 79, y: 23),
                in: size,
                handleSize: handleSize
            ),
            .bottomRight
        )
    }

    func testFitsShortParagraphBelowSourceWhenThereIsRoom() {
        let sourceRect = CGRect(x: 200, y: 520, width: 400, height: 40)
        let layout = ParagraphOverlayLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1040, height: 800),
            anchor: CGPoint(x: sourceRect.midX, y: sourceRect.midY),
            sourceRect: sourceRect
        )

        XCTAssertEqual(
            layout.frame(for: CGSize(width: 520, height: 240)),
            CGRect(x: 200, y: 272, width: 520, height: 240)
        )
    }

    func testFitsShortParagraphAboveSourceWhenSpaceBelowIsTooSmall() {
        let sourceRect = CGRect(x: 200, y: 180, width: 400, height: 40)
        let layout = ParagraphOverlayLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1040, height: 800),
            anchor: CGPoint(x: sourceRect.midX, y: sourceRect.midY),
            sourceRect: sourceRect
        )

        XCTAssertEqual(
            layout.frame(for: CGSize(width: 520, height: 240)),
            CGRect(x: 200, y: 228, width: 520, height: 240)
        )
    }

    func testReadingCardPrefersBelowWithEnoughReadingRoomEvenIfThereIsMoreSpaceAbove() {
        let source = CGRect(x: 200, y: 325, width: 510, height: 42)
        let layout = ParagraphOverlayLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1040, height: 800),
            anchor: CGPoint(x: source.midX, y: source.midY),
            sourceRect: source
        )
        let first = layout.frame(for: CGSize(width: 420, height: 75))
        let expanded = layout.frame(for: CGSize(width: 420, height: 700))
        XCTAssertEqual(first.maxY, source.minY - 8)
        XCTAssertEqual(expanded.maxY, first.maxY)
        XCTAssertEqual(expanded.minY, 8)
    }

    func testCapsLongParagraphToLargerSideOfSource() {
        let sourceRect = CGRect(x: 200, y: 420, width: 400, height: 80)
        let layout = ParagraphOverlayLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1040, height: 800),
            anchor: CGPoint(x: sourceRect.midX, y: sourceRect.midY),
            sourceRect: sourceRect
        )

        XCTAssertEqual(layout.maxPanelSize.height, 404)
        XCTAssertEqual(
            layout.frame(for: CGSize(width: 520, height: 640)),
            CGRect(x: 200, y: 8, width: 520, height: 404)
        )
    }

    func testCapsLongSelectedTextAtScreenEdgesWithoutSourceRect() {
        let screen = CGRect(x: -960, y: -120, width: 960, height: 680)
        let layout = ParagraphOverlayLayout(
            screenFrame: screen,
            anchor: CGPoint(x: -4, y: 556),
            sourceRect: nil
        )
        let inset = ParagraphOverlayLayout.edgeInset
        let frame = layout.frame(for: CGSize(width: 1200, height: 3000))

        XCTAssertEqual(layout.maxPanelSize, CGSize(width: 944, height: 489))
        XCTAssertEqual(frame.size, layout.maxPanelSize)
        XCTAssertTrue(screen.insetBy(dx: inset, dy: inset).contains(frame))
    }

    func testKeepsReadableHeightWhenSourceUsesAlmostEntireScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1040, height: 800)
        let sourceRect = CGRect(x: 200, y: 20, width: 760, height: 760)
        let layout = ParagraphOverlayLayout(
            screenFrame: screen,
            anchor: CGPoint(x: sourceRect.midX, y: sourceRect.midY),
            sourceRect: sourceRect
        )
        let inset = ParagraphOverlayLayout.edgeInset
        let frame = layout.frame(for: CGSize(width: 760, height: 1500))

        XCTAssertEqual(frame.height, 280)
        XCTAssertTrue(screen.insetBy(dx: inset, dy: inset).contains(frame))
    }

    func testDraggedPanelResizesToDestinationScreenAndKeepsTopLeftWhenItFits() {
        let screen = CGRect(x: -480, y: 120, width: 480, height: 400)
        let layout = ParagraphOverlayLayout(screenFrame: screen, anchor: .zero, sourceRect: nil)
        let topLeft = CGPoint(x: -440, y: 480)

        let shortFrame = layout.frame(for: CGSize(width: 380, height: 140), manualTopLeft: topLeft)
        XCTAssertEqual(CGPoint(x: shortFrame.minX, y: shortFrame.maxY), topLeft)

        let inset = ParagraphOverlayLayout.edgeInset
        let largeFrame = layout.frame(for: CGSize(width: 900, height: 1800), manualTopLeft: topLeft)
        XCTAssertEqual(largeFrame.size, CGSize(width: 464, height: 288))
        XCTAssertEqual(largeFrame.maxY, topLeft.y)
        XCTAssertTrue(screen.insetBy(dx: inset, dy: inset).contains(largeFrame))
    }

    @MainActor
    func testReadingViewportFitsShortTextAndScrollsLongTextToTheEnd() throws {
        let headerHeight: CGFloat = 38
        let panelHeightLimit: CGFloat = 300
        for lineCount in [3, 80] {
            let text = (1...lineCount).map { "Translation paragraph \($0)" }.joined(separator: "\n")
            let host = NSHostingView(rootView:
                VStack(spacing: 0) {
                    Text("Toolbar").frame(height: headerHeight)
                    ParagraphReadingViewport {
                        Text(text)
                    }
                }
                .frame(width: 520)
                .frame(maxHeight: panelHeightLimit, alignment: .topLeading)
            )
            let panel = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            panel.contentView = host
            panel.setContentSize(host.fittingSize)
            panel.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()

            if lineCount == 3 {
                XCTAssertLessThan(panel.frame.height, panelHeightLimit)
                XCTAssertNil(firstScrollView(in: host))
            } else {
                let scrollView = try XCTUnwrap(firstScrollView(in: host))
                let document = try XCTUnwrap(scrollView.documentView)
                XCTAssertEqual(scrollView.frame.height, panel.frame.height - headerHeight, accuracy: 1)
                XCTAssertEqual(panel.frame.height, panelHeightLimit, accuracy: 1)
                XCTAssertTrue(scrollView.hasVerticalScroller)
                XCTAssertGreaterThan(document.bounds.height, scrollView.documentVisibleRect.height)
                let initialViewport = scrollView.convert(scrollView.bounds, to: host)
                let offset = document.bounds.height - scrollView.documentVisibleRect.height
                scrollView.contentView.scroll(to: CGPoint(x: 0, y: document.isFlipped ? offset : 0))
                scrollView.reflectScrolledClipView(scrollView.contentView)

                let visibleEnd = document.isFlipped
                    ? scrollView.documentVisibleRect.maxY
                    : scrollView.documentVisibleRect.minY
                let documentEnd = document.isFlipped ? document.bounds.maxY : document.bounds.minY
                XCTAssertEqual(visibleEnd, documentEnd, accuracy: 1)
                XCTAssertEqual(scrollView.convert(scrollView.bounds, to: host), initialViewport)
            }
        }
    }

    @MainActor
    private func firstScrollView(in view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap { self.firstScrollView(in: $0) }.first
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
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            protectedFrames: [
                CGRect(x: 100, y: 100, width: 200, height: 120),
                CGRect(x: 320, y: 100, width: 120, height: 40),
            ]
        )

        XCTAssertTrue(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsOverlayClicks() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 150, y: 150),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            protectedFrames: [CGRect(x: 100, y: 100, width: 200, height: 120)]
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsParagraphRegionClicks() {
        let paragraphRect = CGRect(x: 320, y: 100, width: 120, height: 40)

        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 315, y: 118),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            protectedFrames: [
                CGRect(x: 100, y: 100, width: 200, height: 120),
                paragraphRect,
            ]
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsHighlightWindowClicks() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 330, y: 118),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            protectedFrames: [CGRect(x: 320, y: 100, width: 120, height: 40)]
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyDoesNotDismissWhileParagraphRegionIsInteractive() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: true,
            protectedFrames: []
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyOnlyDismissesPinnedParagraphOverlay() {
        XCTAssertFalse(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isSentenceTranslationPresented: false,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            protectedFrames: []
        ))

        XCTAssertFalse(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: false,
            isRegionInteractionActive: false,
            protectedFrames: []
        ))
    }

    func testOutsideClickPolicyProtectsInPlaceTranslationFrame() {
        let inPlaceFrame = CGRect(x: 420, y: 240, width: 360, height: 100)

        XCTAssertFalse(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 280),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            protectedFrames: [nil, nil, inPlaceFrame]
        ))

        XCTAssertTrue(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 900, y: 500),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            isRegionInteractionActive: false,
            protectedFrames: [nil, nil, inPlaceFrame]
        ))
    }

    func testPersistentSentencePresentationPolicyPresentsExistingTranslation() {
        XCTAssertEqual(
            PersistentSentencePresentationPolicy.resolve(
                isSentenceTranslationPresented: true,
                isRegionInteractionActive: false
            ),
            .presentNow
        )
    }

    func testPersistentSentencePresentationPolicyDefersDuringManualSelection() {
        XCTAssertEqual(
            PersistentSentencePresentationPolicy.resolve(
                isSentenceTranslationPresented: false,
                isRegionInteractionActive: true
            ),
            .deferUntilRegionCompletes
        )
    }

    func testPersistentSentencePresentationPolicyDiscardsUnrelatedRelease() {
        XCTAssertEqual(
            PersistentSentencePresentationPolicy.resolve(
                isSentenceTranslationPresented: false,
                isRegionInteractionActive: false
            ),
            .discard
        )
    }

    func testPersistentOverlayApplicationActivationPolicyDismissesForAnotherApplication() {
        XCTAssertTrue(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: true,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 200,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testPersistentOverlayApplicationActivationPolicyKeepsSourceApplication() {
        XCTAssertFalse(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: true,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 100,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testPersistentOverlayApplicationActivationPolicyKeepsSnapTraActivation() {
        XCTAssertFalse(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: true,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 300,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testPersistentOverlayApplicationActivationPolicyIgnoresTemporaryOverlay() {
        XCTAssertFalse(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: false,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 200,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testTapKeptOverlayPersistenceKeepsSupportedSingleLookupsAfterTap() {
        XCTAssertTrue(TapKeptOverlayPersistencePolicy.shouldKeepAfterTap(
            isEnabled: true,
            lookupKind: .word
        ))

        XCTAssertTrue(TapKeptOverlayPersistencePolicy.shouldKeepAfterTap(
            isEnabled: true,
            lookupKind: .selectedTextSentence
        ))

        XCTAssertFalse(TapKeptOverlayPersistencePolicy.shouldKeepAfterTap(
            isEnabled: false,
            lookupKind: .selectedTextSentence
        ))

        XCTAssertFalse(TapKeptOverlayPersistencePolicy.shouldKeepAfterTap(
            isEnabled: true,
            lookupKind: .ocrSentence
        ))
    }

    func testTapKeptOverlayPersistenceDismissesAfterThresholdMovementOutsideOverlay() {
        let shouldDismiss = TapKeptOverlayPersistencePolicy.shouldDismissOnMouseMove(
            startLocation: CGPoint(x: 100, y: 100),
            currentLocation: CGPoint(x: 140, y: 100),
            overlayFrame: CGRect(x: 200, y: 200, width: 180, height: 120),
            movementThreshold: 16
        )

        XCTAssertTrue(shouldDismiss)
    }

    func testTapKeptOverlayPersistenceKeepsMovementInsideOverlayFrame() {
        let shouldDismiss = TapKeptOverlayPersistencePolicy.shouldDismissOnMouseMove(
            startLocation: CGPoint(x: 100, y: 100),
            currentLocation: CGPoint(x: 220, y: 220),
            overlayFrame: CGRect(x: 200, y: 200, width: 180, height: 120),
            movementThreshold: 16
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testTapKeptOverlayPersistenceKeepsVerticalMovementTowardOffsetOverlay() {
        let shouldDismiss = TapKeptOverlayPersistencePolicy.shouldDismissOnMouseMove(
            startLocation: CGPoint(x: 100, y: 100),
            currentLocation: CGPoint(x: 100, y: 84),
            overlayFrame: CGRect(x: 112, y: 20, width: 180, height: 80),
            movementThreshold: 16
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testEscapeMonitoringPolicyCoversPersistentParagraphAndTapKeptOverlays() {
        XCTAssertTrue(OverlayEscapeDismissalPolicy.shouldMonitor(
            isParagraphOverlayPresented: true,
            isTapKeptOverlayPresented: false
        ))

        XCTAssertTrue(OverlayEscapeDismissalPolicy.shouldMonitor(
            isParagraphOverlayPresented: false,
            isTapKeptOverlayPresented: true
        ))

        XCTAssertFalse(OverlayEscapeDismissalPolicy.shouldMonitor(
            isParagraphOverlayPresented: false,
            isTapKeptOverlayPresented: false
        ))
    }

    func testParagraphOverlayControlPolicyShowsCloseForTapKeptOverlay() {
        XCTAssertTrue(ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: true,
            isParagraphOverlayPinned: false,
            isTapKeptOverlay: false
        ))

        XCTAssertFalse(ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: true,
            isParagraphOverlayPinned: false,
            isTapKeptOverlay: true
        ))

        XCTAssertFalse(ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: true,
            isParagraphOverlayPinned: true,
            isTapKeptOverlay: false
        ))
    }

    func testWordOverlayTextSelectionPolicyUsesSelectableTextOnlyWhenInteractive() {
        XCTAssertTrue(WordOverlayTextSelectionPolicy.usesSelectableText(
            isWordOverlayMode: true,
            showsWordOverlayControls: true
        ))

        XCTAssertFalse(WordOverlayTextSelectionPolicy.usesSelectableText(
            isWordOverlayMode: true,
            showsWordOverlayControls: false
        ))

        XCTAssertFalse(WordOverlayTextSelectionPolicy.usesSelectableText(
            isWordOverlayMode: false,
            showsWordOverlayControls: true
        ))
    }

    func testWordOverlayHeaderLayoutReservesControlsOutsideIdentityGroup() {
        let metrics = WordOverlayHeaderLayoutPolicy.resolve(
            panelWidth: 380,
            horizontalPadding: 18,
            controlGroupWidth: 54,
            gapBetweenIdentityAndControls: 12
        )

        XCTAssertEqual(metrics.identityGroupMaxWidth, 278, accuracy: 0.001)
        XCTAssertEqual(metrics.titleMaxWidth, 278, accuracy: 0.001)
    }

    func testWordOverlayHeaderLayoutKeepsPhoneticBadgeReadable() {
        let metrics = WordOverlayHeaderLayoutPolicy.resolve(
            panelWidth: 380,
            horizontalPadding: 18,
            controlGroupWidth: 54,
            gapBetweenIdentityAndControls: 12
        )

        XCTAssertFalse(metrics.allowsPhoneticBadgeHorizontalCompression)
    }

    func testWordOverlayHeaderLayoutNormalizesDisplayedPhonetic() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.displayedPhonetic("  pəˈtɪkjʊlə  "),
            "pəˈtɪkjʊlə"
        )
        XCTAssertNil(WordOverlayHeaderLayoutPolicy.displayedPhonetic(" \n\t "))
        XCTAssertNil(WordOverlayHeaderLayoutPolicy.displayedPhonetic(nil))
    }

    func testOriginalVisibilityShowsEditableOriginalWhenHideSettingIsOffAndOverlayIsPinned() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: false,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityHidesOriginalWhenHideSettingIsOnAndPinnedEditorIsCollapsed() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false
        )

        XCTAssertFalse(decision.showsOriginalTextRegion)
        XCTAssertFalse(decision.usesEditableOriginalText)
        XCTAssertTrue(decision.showsOriginalEditorToggle)
        XCTAssertTrue(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityShowsEditableFallbackWhenHideSettingIsOnAndPinnedOriginalTextIsMissing() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: false,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityKeepsManualInputFallbackVisibleAfterTextEntry() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: true
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityShowsEditableOriginalWhenHideSettingIsOnAndPinnedEditorIsExpanded() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: true,
            isManualInputFallback: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertTrue(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityHidesOriginalWhenHideSettingIsOnAndOverlayIsNotPinned() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: false,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: true,
            isManualInputFallback: false
        )

        XCTAssertFalse(decision.showsOriginalTextRegion)
        XCTAssertFalse(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertTrue(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityShowsOriginalWhenNoTranslationOutputExists() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: false,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false,
            hasTranslationOutput: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertFalse(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testParagraphHighlightConvertsScreenLineRectsToTopLeftLocalSpace() {
        let windowFrame = CGRect(x: 100, y: 200, width: 300, height: 120)
        let lineRects = [
            CGRect(x: 110, y: 280, width: 200, height: 24),
            CGRect(x: 120, y: 220, width: 180, height: 18),
        ]

        XCTAssertEqual(
            ParagraphHighlightLayout.localLineRects(
                in: windowFrame,
                lineRects: lineRects
            ),
            [
                CGRect(x: 10, y: 16, width: 200, height: 24),
                CGRect(x: 20, y: 82, width: 180, height: 18),
            ]
        )
    }

    func testParagraphHighlightClipsScreenLineRectsAndFallsBackWhenNoneRemain() {
        let windowFrame = CGRect(x: 100, y: 200, width: 300, height: 120)

        XCTAssertEqual(
            ParagraphHighlightLayout.localLineRects(
                in: windowFrame,
                lineRects: [CGRect(x: 90, y: 310, width: 40, height: 30)]
            ),
            [CGRect(x: 0, y: 0, width: 30, height: 10)]
        )
        XCTAssertEqual(
            ParagraphHighlightLayout.localLineRects(
                in: windowFrame,
                lineRects: [
                    .zero,
                    CGRect(x: 500, y: 500, width: 20, height: 20),
                ]
            ),
            [CGRect(origin: .zero, size: windowFrame.size)]
        )
        XCTAssertEqual(
            ParagraphHighlightLayout.localLineRects(
                in: windowFrame,
                lineRects: []
            ),
            [CGRect(origin: .zero, size: windowFrame.size)]
        )
    }

    func testParagraphHighlightUsesTwoPointLeadingGuideAndStrongerContrast() {
        let normal = ParagraphHighlightVisualStyle.resolve(increaseContrast: false)
        let increased = ParagraphHighlightVisualStyle.resolve(increaseContrast: true)

        XCTAssertEqual(ParagraphHighlightVisualStyle.leadingGuideWidth, 2)
        XCTAssertLessThan(normal.fillOpacity, 0.15)
        XCTAssertGreaterThan(increased.fillOpacity, normal.fillOpacity)
        XCTAssertGreaterThan(increased.leadingGuideOpacity, normal.leadingGuideOpacity)
    }

    func testParagraphHighlightHandlesAppearOnlyForHoverDragOrExplicitAdjustment() {
        XCTAssertFalse(ParagraphHighlightHandleVisibility.isVisible(
            for: .topLeft,
            hoveredCorner: nil,
            activeCorner: nil,
            isAdjusting: false
        ))
        XCTAssertTrue(ParagraphHighlightHandleVisibility.isVisible(
            for: .topLeft,
            hoveredCorner: .topLeft,
            activeCorner: nil,
            isAdjusting: false
        ))
        XCTAssertTrue(ParagraphHighlightHandleVisibility.isVisible(
            for: .topLeft,
            hoveredCorner: nil,
            activeCorner: .topLeft,
            isAdjusting: false
        ))
        XCTAssertTrue(ParagraphHighlightHandleVisibility.isVisible(
            for: .bottomRight,
            hoveredCorner: nil,
            activeCorner: nil,
            isAdjusting: true
        ))
        XCTAssertFalse(ParagraphHighlightHandleVisibility.isVisible(
            for: .bottomRight,
            hoveredCorner: .topLeft,
            activeCorner: nil,
            isAdjusting: false
        ))
    }

    func testParagraphHighlightEntranceHonorsReduceMotion() {
        XCTAssertEqual(
            ParagraphHighlightEntrancePolicy.resolve(reduceMotion: false).duration,
            0.11,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ParagraphHighlightEntrancePolicy.resolve(reduceMotion: true).duration,
            0
        )
    }

    func testParagraphReadingCardKeepsOneSideWhileStreamingTextGrows() {
        let sourceRect = CGRect(x: 200, y: 180, width: 400, height: 40)
        let layout = ParagraphOverlayLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1040, height: 800),
            anchor: CGPoint(x: sourceRect.midX, y: sourceRect.midY),
            sourceRect: sourceRect
        )

        let shortFrame = layout.frame(for: CGSize(width: 520, height: 80))
        let longFrame = layout.frame(for: CGSize(width: 520, height: 640))

        XCTAssertGreaterThanOrEqual(shortFrame.minY, sourceRect.maxY)
        XCTAssertGreaterThanOrEqual(longFrame.minY, sourceRect.maxY)
        XCTAssertEqual(shortFrame.minY, longFrame.minY)
    }

    func testParagraphReadingCardStaysBelowWhenThereIsMoreRoomBelow() {
        let sourceRect = CGRect(x: 200, y: 680, width: 400, height: 40)
        let layout = ParagraphOverlayLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1040, height: 800),
            anchor: CGPoint(x: sourceRect.midX, y: sourceRect.midY),
            sourceRect: sourceRect
        )

        let shortFrame = layout.frame(for: CGSize(width: 520, height: 80))
        let longFrame = layout.frame(for: CGSize(width: 520, height: 640))

        XCTAssertLessThanOrEqual(shortFrame.maxY, sourceRect.minY)
        XCTAssertLessThanOrEqual(longFrame.maxY, sourceRect.minY)
    }

    func testParagraphReadingCardEntranceMovesFourPointsTowardSourceAndFadesIn() {
        let sourceRect = CGRect(x: 200, y: 520, width: 400, height: 40)
        let frameBelowSource = CGRect(x: 200, y: 380, width: 520, height: 132)
        let frameAboveSource = CGRect(x: 200, y: 568, width: 520, height: 132)

        let below = ParagraphReadingCardEntrance.resolve(
            finalFrame: frameBelowSource,
            sourceRect: sourceRect,
            reduceMotion: false
        )
        let above = ParagraphReadingCardEntrance.resolve(
            finalFrame: frameAboveSource,
            sourceRect: sourceRect,
            reduceMotion: false
        )

        XCTAssertEqual(
            below.initialFrame,
            frameBelowSource.offsetBy(dx: 0, dy: 4)
        )
        XCTAssertEqual(
            above.initialFrame,
            frameAboveSource.offsetBy(dx: 0, dy: -4)
        )
        XCTAssertEqual(below.initialOpacity, 0)
        XCTAssertEqual(below.duration, 0.16, accuracy: 0.0001)
    }

    func testParagraphReadingCardEntranceSkipsMotionForReducedMotion() {
        let finalFrame = CGRect(x: 200, y: 380, width: 520, height: 132)
        let entrance = ParagraphReadingCardEntrance.resolve(
            finalFrame: finalFrame,
            sourceRect: CGRect(x: 200, y: 520, width: 400, height: 40),
            reduceMotion: true
        )

        XCTAssertEqual(entrance.initialFrame, finalFrame)
        XCTAssertEqual(entrance.initialOpacity, 1)
        XCTAssertEqual(entrance.duration, 0)
    }
}
