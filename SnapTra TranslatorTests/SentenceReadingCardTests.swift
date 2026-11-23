import SwiftUI
import SwiftData
import XCTest
@testable import SnapTra_Translator

@MainActor
final class SentenceReadingCardTests: XCTestCase {
    func testWaitsOnlyWhileAllEnabledSourcesArePending() {
        var content = ParagraphOverlayContent(
            originalText: "Together AI model catalog now includes embedding and rerank model types.",
            translationState: .loading,
            serviceResults: [ServiceTranslationResult(sourceType: .omlx, modelName: nil, state: .loading)],
        )
        XCTAssertTrue(OverlayState.paragraphLoading.waitsForFirstParagraphOutput(hidesOriginalText: true))
        XCTAssertTrue(OverlayState.paragraphResult(content).waitsForFirstParagraphOutput(hidesOriginalText: true))
        XCTAssertFalse(OverlayState.paragraphResult(content).waitsForFirstParagraphOutput(hidesOriginalText: false))

        content.serviceResults[0].state = .ready("Together AI 的模型目录")
        XCTAssertFalse(OverlayState.paragraphResult(content).waitsForFirstParagraphOutput(hidesOriginalText: true))
        content.serviceResults[0].state = .loading
        content.translationState = .failed("Unavailable")
        XCTAssertFalse(OverlayState.paragraphResult(content).waitsForFirstParagraphOutput(hidesOriginalText: true))
        content.showsNativeTranslation = false
        XCTAssertTrue(OverlayState.paragraphResult(content).waitsForFirstParagraphOutput(hidesOriginalText: true))
    }

    func testFailedRecognitionAndManualInputAppearImmediately() {
        let errorState = OverlayState.paragraphResult(ParagraphOverlayContent(translationState: .failed("No text")))
        XCTAssertFalse(errorState.waitsForFirstParagraphOutput(hidesOriginalText: true))
        let input = OverlayState.paragraphResult(ParagraphOverlayContent(
            translationState: .loading,
            isManualInputFallback: true,
        ))
        XCTAssertFalse(input.waitsForFirstParagraphOutput(hidesOriginalText: true))

        let emptyTextEntry = OverlayState.paragraphResult(ParagraphOverlayContent(
            translationState: .failed(""),
            showsNativeTranslation: false,
            isManualInputFallback: true,
            isManualTextEntry: true,
        ))
        XCTAssertFalse(emptyTextEntry.waitsForFirstParagraphOutput(hidesOriginalText: true))
    }

    private func makeModel() throws -> AppModel {
        let suite = "SentenceReadingCardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)
        settings.learningEnabled = false
        let container = try ModelContainer(for: WordRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return AppModel(settings: settings, modelContext: container.mainContext)
    }

    func testWordDirectionUsesTheClickedTextAndHonorsBidirectionalLookupForMixedScripts() {
        let paragraph = ParagraphOverlayContent(
            translationState: .ready("I use Antigravity."),
            sourceLanguageIdentifier: "zh-Hans", selectedTargetLanguageIdentifier: "en"
        )
        let pair = LookupLanguagePair(sourceIdentifier: "zh-Hans", targetIdentifier: "en")
        XCTAssertEqual(paragraph.wordLanguagePair(for: "use", from: .translation, bidirectional: false), pair.reversed())
        XCTAssertEqual(paragraph.wordLanguagePair(for: "使用", from: .original, bidirectional: false), pair)
        XCTAssertEqual(paragraph.wordLanguagePair(for: "Antigravity", from: .original, bidirectional: true), pair.reversed())
    }

    func testLookingUpWordsInAReadingCardKeepsItsTranslationAndDismissesInOrder() async throws {
        let model = try makeModel()
        defer { model.dismissOverlay() }
        model.settings.continuousTranslation = false
        model.settings.playWordPronunciation = false
        model.settings.copyWord = false
        model.settings.dictionarySources = []
        model.settings.hideOriginalTextInSentenceOverlay = false
        model.settings.sentenceTranslationPresentationMode = .overlayPanel

        var paragraph = ParagraphOverlayContent(
            originalText: "朋友们在讨论黑色星期五。",
            translationState: .ready("Friends are discussing Black Friday."),
            serviceResults: [.init(sourceType: .omlx, modelName: nil, state: .loading)],
            sourceLanguageIdentifier: "zh-Hans",
            selectedTargetLanguageIdentifier: "en"
        )
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let anchor = CGPoint(x: screen.midX, y: screen.midY)
        model.updateOverlay(state: .paragraphResult(paragraph), anchor: anchor)
        let parent = try XCTUnwrap(model.overlayWindowController.window)
        let root = try XCTUnwrap(parent.contentView)

        func textView(containing word: String, in view: NSView) -> WordLookupTextView? {
            if let text = view as? WordLookupTextView, text.string.contains(word) { return text }
            return view.subviews.lazy.compactMap { textView(containing: word, in: $0) }.first
        }
        func lookup(_ word: String) async throws -> OverlayContent {
            model.overlayWindowController.refreshLayoutIfNeeded()
            parent.layoutIfNeeded()
            let text = try XCTUnwrap(textView(containing: word, in: root))
            let container = try XCTUnwrap(text.textContainer)
            let layout = try XCTUnwrap(text.layoutManager)
            layout.ensureLayout(for: container)
            let range = (text.string as NSString).range(of: word)
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let glyphCenter = CGPoint(x: text.textContainerOrigin.x + rect.midX, y: text.textContainerOrigin.y + rect.midY)
            let layoutDeadline = ContinuousClock.now + .seconds(1)
            while root.hitTest(text.convert(glyphCenter, to: nil)) !== text, ContinuousClock.now < layoutDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let point = text.convert(glyphCenter, to: nil)
            XCTAssertTrue(root.hitTest(point) === text, "Expected the visible glyph of \(word) to receive the click")
            for count in 1...2 {
                func event(_ type: NSEvent.EventType) throws -> NSEvent {
                    try XCTUnwrap(NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: parent.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1
                    ))
                }
                NSApp.postEvent(try event(.leftMouseUp), atStart: true)
                parent.sendEvent(try event(.leftMouseDown))
            }
            let deadline = ContinuousClock.now + .seconds(1)
            while model.paragraphWordContent?.word != word, ContinuousClock.now < deadline {
                await Task.yield()
            }
            let content = try XCTUnwrap(model.paragraphWordContent)
            XCTAssertEqual(content.word, word)
            XCTAssertEqual(text.selectedRange(), range)
            return content
        }

        let translatedWord = try await lookup("Friday")
        XCTAssertEqual(translatedWord.sourceLanguageIdentifier, "en")
        XCTAssertEqual(translatedWord.targetLanguageIdentifier, "zh-Hans")
        let child = try XCTUnwrap(model.paragraphWordWindowController.window)
        XCTAssertTrue(child.isVisible)
        XCTAssertTrue(child.parent === parent)

        paragraph.serviceResults[0].state = .ready("They are talking about Black Friday.")
        model.updateOverlay(state: .paragraphResult(paragraph))
        XCTAssertEqual(model.paragraphWordContent?.word, "Friday")
        let alternative = try await lookup("talking")
        XCTAssertEqual(alternative.targetLanguageIdentifier, "zh-Hans")
        let originalWord = try await lookup("朋友")
        XCTAssertEqual(originalWord.sourceLanguageIdentifier, "zh-Hans")
        XCTAssertEqual(originalWord.targetLanguageIdentifier, "en")
        XCTAssertTrue(model.paragraphWordWindowController.window === child)
        XCTAssertEqual(model.overlayState, .paragraphResult(paragraph))

        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: parent.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        XCTAssertTrue(model.handleOverlayEscapeKey(escape))
        XCTAssertNil(model.paragraphWordContent)
        XCTAssertFalse(child.isVisible)
        XCTAssertTrue(parent.isVisible)
        XCTAssertEqual(model.overlayState, .paragraphResult(paragraph))
        XCTAssertTrue(model.handleOverlayEscapeKey(escape))
        XCTAssertFalse(parent.isVisible)
    }

    func testCursorLineScanSurvivesPersistentReleaseBeforeOrAfterRecognition() throws {
        let model = try makeModel()
        defer { model.dismissOverlay() }
        let lineRect = CGRect(x: 104, y: 320, width: 512, height: 18)
        let anchor = CGPoint(x: lineRect.midX, y: lineRect.midY)
        let content = ParagraphOverlayContent(originalText: "我用 AI 给 Java 写了个指标", translationState: .loading)

        for releaseBeforeResult in [false, true] {
            model.overlayState = .paragraphLoading
            if releaseBeforeResult { model.handlePersistentSentenceOverlayRelease() }
            model.setParagraphSourceRegion(lineRect, selectionMode: .cursorParagraph)
            model.updateOverlay(state: .paragraphResult(content), anchor: anchor)
            if !releaseBeforeResult { model.handlePersistentSentenceOverlayRelease() }
            XCTAssertTrue(model.isParagraphOverlayPinned)
            XCTAssertEqual(model.visibleSourceHighlightFrame, lineRect)

            var translated = content
            translated.translationState = .ready("I wrote a Java metric using AI.")
            model.updateOverlay(state: .paragraphResult(translated))
            XCTAssertEqual(model.visibleSourceHighlightFrame, lineRect)
            model.dismissOverlay()
            XCTAssertNil(model.visibleSourceHighlightFrame)
        }
    }

    func testContentRefreshKeepsCursorToSourceMotionInFlight() async throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let model = try makeModel()
        defer { model.dismissOverlay() }
        model.settings.continuousTranslation = false
        model.settings.hideOriginalTextInSentenceOverlay = false
        model.settings.sentenceTranslationPresentationMode = .overlayPanel

        let sourceRect = CGRect(x: screen.minX + 24, y: screen.midY + 60, width: 400, height: 24)
        let anchor = CGPoint(x: sourceRect.minX + 100, y: sourceRect.midY)
        let controller = model.overlayWindowController
        let window = try XCTUnwrap(controller.window)
        model.updateOverlay(state: .paragraphLoading, anchor: anchor)
        let presentationDeadline = ContinuousClock.now + .seconds(1)
        while !controller.isVisible, ContinuousClock.now < presentationDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let startFrame = try XCTUnwrap(controller.visibleFrame)
        let initialOpacity = window.alphaValue
        XCTAssertGreaterThan(startFrame.minX, sourceRect.minX)

        model.setParagraphSourceRegion(sourceRect, selectionMode: .cursorParagraph)
        var content = ParagraphOverlayContent(
            originalText: "A sentence to translate",
            translationState: .loading
        )
        model.updateOverlay(state: .paragraphResult(content))
        controller.refreshLayoutIfNeeded(at: anchor)
        XCTAssertEqual(controller.visibleFrame?.minX, startFrame.minX)
        XCTAssertEqual(window.alphaValue, initialOpacity)

        let deadline = ContinuousClock.now + .seconds(1)
        var didRefreshDuringMotion = false
        while ContinuousClock.now < deadline {
            let frame = try XCTUnwrap(controller.visibleFrame)
            if !didRefreshDuringMotion, frame.minX > sourceRect.minX + 1, frame.minX < startFrame.minX {
                let opacity = window.alphaValue
                content.translationState = .ready("第一段译文。\n第二段译文。")
                model.updateOverlay(state: .paragraphResult(content))
                controller.refreshLayoutIfNeeded(at: anchor)
                XCTAssertEqual(controller.visibleFrame?.minX, frame.minX)
                XCTAssertEqual(window.alphaValue, opacity)
                didRefreshDuringMotion = true
            }
            if frame.minX == sourceRect.minX, window.alphaValue == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let settledFrame = try XCTUnwrap(controller.visibleFrame)
        XCTAssertTrue(didRefreshDuringMotion)
        XCTAssertEqual(settledFrame.minX, sourceRect.minX)
        XCTAssertEqual(settledFrame.maxY, sourceRect.minY - 8, accuracy: 0.5)
        XCTAssertGreaterThan(settledFrame.height, startFrame.height)
        XCTAssertEqual(window.alphaValue, 1)
    }

    func testWordLookupClearsPreviousSentenceScanAndKeepsOnlyTheCardAfterTap() throws {
        let model = try makeModel()
        defer { model.dismissOverlay() }
        model.settings.keepWordOverlayAfterTap = true
        let sentenceRect = CGRect(x: 184, y: 264, width: 320, height: 32)
        model.setParagraphSourceRegion(sentenceRect, selectionMode: .cursorParagraph)
        XCTAssertEqual(model.visibleSourceHighlightFrame, sentenceRect)
        model.handleHotkeyTrigger()
        XCTAssertNil(model.visibleSourceHighlightFrame)
        XCTAssertNil(model.activeParagraphRect)

        var content = OverlayContent(
            word: "Table",
            phonetic: nil,
            primaryTranslationState: .loading,
            usesCompactPrimaryTranslationStyle: false
        )
        model.updateOverlay(state: .result(content), anchor: sentenceRect.origin)
        XCTAssertNil(model.visibleSourceHighlightFrame)
        model.handleHotkeyTapRelease()
        content.primaryTranslationState = .ready("餐桌", isFallback: false)
        model.updateOverlay(state: .result(content))
        XCTAssertTrue(model.isTapKeptOverlayPresented)
        XCTAssertEqual(model.overlayState, .result(content))
        XCTAssertNil(model.visibleSourceHighlightFrame)
    }

    func testManualSelectionKeepsItsAnchorWithoutStartingOrRetainingAnAutomaticScan() throws {
        let model = try makeModel()
        defer { model.dismissOverlay() }
        model.settings.doubleTapSentenceTranslationMode = .cursorParagraph
        let automatic = CGRect(x: 100, y: 220, width: 400, height: 22)
        let manual = automatic.insetBy(dx: -8, dy: -4)
        model.setParagraphSourceRegion(automatic, selectionMode: .cursorParagraph)
        XCTAssertEqual(model.visibleSourceHighlightFrame, automatic)

        model.setParagraphSourceRegion(manual, selectionMode: .manualRegion)
        model.overlayState = .paragraphLoading
        model.handlePersistentSentenceOverlayRelease()
        model.updateOverlay(state: .paragraphResult(
            ParagraphOverlayContent(originalText: "Table", translationState: .ready("表格"))
        ))
        XCTAssertTrue(model.isParagraphOverlayPinned)
        XCTAssertEqual(model.activeParagraphRect, manual)
        XCTAssertNil(model.visibleSourceHighlightFrame)
    }

    func testNativeCardKeepsItsReadingWidthAsTranslationStreams() throws {
        let model = try makeModel()
        let source = "Together AI model catalog now includes embedding and rerank model types."
        let translation = "Together AI 的模型目录现已收录嵌入模型和重排序模型。"
        var content = ParagraphOverlayContent(
            originalText: source,
            translationState: .loading,
            showsNativeTranslation: false,
            serviceResults: [.init(sourceType: .omlx, modelName: "Hy-MT2-1.8B-Abliterated-8bit", state: .ready(translation), duration: 0.95, isComplete: true)],
            languageOptions: [.init(identifier: "en", displayName: "英语"), .init(identifier: "zh-Hans", displayName: "简体中文")],
            sourceLanguageIdentifier: "en",
            selectedTargetLanguageIdentifier: "zh-Hans",
        )
        func host(width: CGFloat, appearance: ColorScheme) -> NSHostingView<some View> {
            model.overlayState = .paragraphResult(content)
            return NSHostingView(rootView: OverlayView(paragraphOverlayMaxSize: CGSize(width: width, height: 500))
                .environmentObject(model)
                .environment(\.colorScheme, appearance))
        }

        for appearance in [ColorScheme.dark, .light] {
            let view = host(width: 800, appearance: appearance)
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.contentView = view
            let size = view.fittingSize
            XCTAssertEqual(size.width, 420, accuracy: 1)
            XCTAssertGreaterThan(size.height, 40)
            panel.setContentSize(size)
            panel.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThan(size.height, 95)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "Sentence reading card \(appearance == .dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        content.serviceResults[0].state = .ready(String(repeating: translation, count: 20))
        content.serviceResults[0].isComplete = false
        XCTAssertEqual(host(width: 800, appearance: .dark).fittingSize.width, 420, accuracy: 1)
        content.originalText = Array(repeating: source, count: 5).joined(separator: "\n")
        XCTAssertEqual(host(width: 800, appearance: .dark).fittingSize.width, 500, accuracy: 1)
        XCTAssertEqual(host(width: 335, appearance: .dark).fittingSize.width, 335, accuracy: 1)
    }

    func testStreamingCardOnlyScrollsWhenItExceedsThePanelHeightLimit() throws {
        let model = try makeModel()
        let limit = CGSize(width: 800, height: 280)
        let view = NSHostingView(rootView: OverlayView(paragraphOverlayMaxSize: limit).environmentObject(model))
        let panel = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        panel.contentView = view
        var content = ParagraphOverlayContent(
            originalText: "A short source sentence.",
            translationState: .loading,
            showsNativeTranslation: false,
            serviceResults: [.init(sourceType: .omlx, modelName: nil, state: .loading)],
        )
        model.overlayState = .paragraphResult(content)

        func publish(_ text: String, isComplete: Bool = false) {
            content.serviceResults[0].state = .ready(text)
            content.serviceResults[0].isComplete = isComplete
            model.overlayState = .paragraphResult(content)
            view.layoutSubtreeIfNeeded()
        }
        func resizePanel() {
            panel.setContentSize(view.fittingSize)
            panel.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
        }
        resizePanel()

        let translation = String(repeating: "这是一段逐字显示的译文。", count: 7)
        var partial = ""
        var transientScrollerOffsets: [Int] = []
        var settledHeights: Set<CGFloat> = []
        for character in translation {
            partial.append(character)
            publish(partial)
            if firstScrollView(in: view) != nil {
                transientScrollerOffsets.append(partial.count)
            }
            resizePanel()
            settledHeights.insert(panel.frame.height)
        }
        XCTAssertEqual(settledHeights.count, 4)
        XCTAssertLessThan(panel.frame.height, limit.height)
        XCTAssertEqual(transientScrollerOffsets, [])
        XCTAssertNil(firstScrollView(in: view))

        let longTranslation = String(repeating: translation, count: 8)
        publish(longTranslation)
        resizePanel()
        XCTAssertEqual(panel.frame.height, limit.height, accuracy: 1)
        let scrollView = try XCTUnwrap(firstScrollView(in: view))
        XCTAssertTrue(scrollView.hasVerticalScroller)
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: 36))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        publish(longTranslation + "完。", isComplete: true)
        resizePanel()
        XCTAssertTrue(firstScrollView(in: view) === scrollView)
        XCTAssertEqual(scrollView.documentVisibleRect.minY, 36, accuracy: 1)

        publish("下一句。", isComplete: true)
        resizePanel()
        XCTAssertNil(firstScrollView(in: view))
        XCTAssertEqual(panel.frame.height, try XCTUnwrap(settledHeights.min()), accuracy: 1)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap { self.firstScrollView(in: $0) }.first
    }
}

extension SentenceReadingCardTests {
    func testParagraphWordPanelFitsShortTextAndScrollsLongTextToTheEnd() async throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Word translation requires macOS 15") }
        let model = try makeModel()
        defer { model.dismissOverlay() }
        model.settings.dictionarySources = []
        model.settings.playWordPronunciation = false
        model.settings.copyWord = false
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        model.overlayState = .paragraphResult(ParagraphOverlayContent(
            originalText: "Read a word here.", translationState: .ready("Read a word here."),
            sourceLanguageIdentifier: "en", selectedTargetLanguageIdentifier: "en"
        ))
        let parent = model.overlayWindowController
        parent.show(at: CGPoint(x: screen.midX, y: screen.midY))
        let paragraph = try XCTUnwrap(parent.visibleFrame)
        let anchor = CGPoint(x: paragraph.midX, y: paragraph.midY)
        let limit = ParagraphWordPanelLayout(screenFrame: screen, paragraphFrame: paragraph, anchor: anchor).maxPanelSize

        // The same-language result displays the supplied text without contacting a service.
        let longText = Array(repeating: "A long definition with an example.", count: 180).joined(separator: "\n")
        for text in ["word", longText] {
            model.lookupParagraphWord(text, from: .original, at: anchor)
            let deadline = ContinuousClock.now + .seconds(2)
            while model.paragraphWordContent?.word != text, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(model.paragraphWordContent?.word, text)
            let controller = model.paragraphWordWindowController
            controller.refreshLayoutIfNeeded()
            let window = try XCTUnwrap(controller.window)
            let view = try XCTUnwrap(window.contentView)
            window.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(window.parent === parent.window)
            XCTAssertTrue(screen.insetBy(dx: 7, dy: 7).contains(window.frame))
            XCTAssertEqual(window.frame.width, limit.width, accuracy: 1)

            if text == "word" {
                XCTAssertLessThan(window.frame.height, limit.height)
                XCTAssertNil(firstScrollView(in: view))
            } else {
                XCTAssertEqual(window.frame.height, limit.height, accuracy: 1)
                let scroll = try XCTUnwrap(firstScrollView(in: view))
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertGreaterThan(document.bounds.height, scroll.documentVisibleRect.height)
                let bottom = document.bounds.maxY - scroll.documentVisibleRect.height
                scroll.contentView.scroll(to: CGPoint(x: 0, y: document.isFlipped ? bottom : 0))
                scroll.reflectScrolledClipView(scroll.contentView)
                let visibleEnd = document.isFlipped ? scroll.documentVisibleRect.maxY : scroll.documentVisibleRect.minY
                XCTAssertEqual(visibleEnd, document.isFlipped ? document.bounds.maxY : document.bounds.minY, accuracy: 1)
            }
        }
    }
}

@MainActor
final class WordLookupTextViewTests: XCTestCase {
    func testDigitInsideAWordUsesTheWholeWord() throws {
        let view = makeTextView("H2O 123")
        XCTAssertEqual(view.wordRange(at: try point(over: "2", in: view)), (view.string as NSString).range(of: "H2O"))
        XCTAssertNil(view.wordRange(at: try point(over: "3", in: view)))
    }

    func testWrappedTextUsesTheClickedGlyphAndNativeWordBoundaries() throws {
        let view = makeTextView("✈️ first word e\u{301}cole, 北京欢迎你")
        let first = try point(over: "f", in: view)
        let accentedLetter = try point(over: "e\u{301}", in: view)
        XCTAssertGreaterThan(accentedLetter.y, first.y)

        let text = view.string as NSString
        XCTAssertEqual(view.wordRange(at: accentedLetter), text.range(of: "e\u{301}cole"))
        XCTAssertEqual(view.wordRange(at: try point(over: "京", in: view)), text.range(of: "北京"))
        XCTAssertNil(view.wordRange(at: try point(over: " ", in: view)))
        XCTAssertNil(view.wordRange(at: try point(over: ",", in: view)))
        XCTAssertNil(view.wordRange(at: try point(over: "✈️", in: view)))
        let lastGlyph = try point(over: "你", in: view)
        XCTAssertNil(view.wordRange(at: NSPoint(x: view.bounds.maxX - 1, y: lastGlyph.y)))
        XCTAssertNil(view.wordRange(at: NSPoint(x: lastGlyph.x, y: view.bounds.maxY - 1)))
    }

    func testNativeDoubleClickReportsTheSelectedWordAndScreenPoint() throws {
        let view = makeTextView("one two")
        let panel = NSPanel(
            contentRect: view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        let pointInWindow = view.convert(try point(over: "w", in: view), to: nil)
        var lookedUpWords: [String] = []
        view.onWordDoubleClick = { word, screenPoint in
            lookedUpWords.append(word)
            XCTAssertEqual(screenPoint, panel.convertPoint(toScreen: pointInWindow))
        }
        defer { view.onWordDoubleClick = nil }

        for count in 1...2 {
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: pointInWindow, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: count, clickCount: count, pressure: 1
                ))
            }
            // NSTextView tracks mouse-up synchronously inside mouseDown.
            NSApp.postEvent(try event(.leftMouseUp), atStart: true)
            view.mouseDown(with: try event(.leftMouseDown))
            XCTAssertEqual(lookedUpWords, count == 1 ? [] : ["two"])
        }
        XCTAssertEqual(view.selectedRange(), (view.string as NSString).range(of: "two"))
    }

    private func makeTextView(_ text: String) -> WordLookupTextView {
        let view = WordLookupTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 260))
        view.isEditable = false
        view.isSelectable = true
        view.font = .systemFont(ofSize: 16)
        view.textContainerInset = NSSize(width: 8, height: 5)
        view.string = text
        return view
    }

    private func point(over character: String, in view: NSTextView) throws -> NSPoint {
        let container = try XCTUnwrap(view.textContainer)
        let layout = try XCTUnwrap(view.layoutManager)
        layout.ensureLayout(for: container)
        let range = (view.string as NSString).range(of: character)
        let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        return NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
    }
}
