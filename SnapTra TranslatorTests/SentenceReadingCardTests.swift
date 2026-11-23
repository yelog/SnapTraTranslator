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

    private func makeModel(suite: String = "SentenceReadingCardTests.\(UUID().uuidString)") throws -> AppModel {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)
        settings.learningEnabled = false
        let container = try ModelContainer(for: WordRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return AppModel(settings: settings, modelContext: container.mainContext)
    }

    func testDismissingOverlayPreservesDisplayedLanguagePackStatus() async throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("Translation requires macOS 15") }
        let model = try makeModel()
        let manager = try XCTUnwrap(model.languagePackManager)
        let status = await manager.checkLanguagePairQuiet(from: "en", to: "ja")
        model.dismissOverlay()
        XCTAssertEqual(manager.getStatus(from: "en", to: "ja"), status)
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
        model.settings.sentenceTranslationSources = [
            .init(id: UUID(), type: .omlx, isEnabled: true),
            .init(id: UUID(), type: .native, isEnabled: true),
        ]

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

    func testCompactResultFollowsProviderOrderAndUsesAvailableOutput() {
        let priority: [SentenceTranslationSource.SourceType] = [.bing, .native, .omlx]
        var content = ParagraphOverlayContent(
            originalText: "Press Start", translationState: .ready("开始"),
            serviceResults: [
                .init(sourceType: .bing, modelName: nil, state: .loading),
                .init(sourceType: .omlx, modelName: nil, state: .ready("按开始")),
            ]
        )
        func sources() -> ParagraphReadingSources {
            ParagraphReadingSources(content: content, priority: priority)
        }
        XCTAssertEqual(sources().results.map(\.sourceType), priority)
        XCTAssertEqual(sources().primary.sourceType, .native)
        content.serviceResults[0].state = .ready("按下开始键")
        XCTAssertEqual(sources().primary.sourceType, .bing)
        XCTAssertEqual(sources().visibleResults(expanded: false).map(\.sourceType), [.bing])
        XCTAssertEqual(sources().visibleResults(expanded: true).map(\.sourceType), priority)
        content.serviceResults[0].state = .failed("Unavailable")
        content.translationState = .ready("  ")
        XCTAssertEqual(sources().primary.sourceType, .omlx)
        content.serviceResults[1].state = .loading
        XCTAssertEqual(sources().primary.sourceType, .bing)
        XCTAssertEqual(sources().primary.state, .failed("Unavailable"))
    }

    func testComparisonButtonExpandsAndCollapsesBothTranslationsAndCopiesThePrimary() async throws {
        let model = try makeModel()
        model.settings.sentenceTranslationSources = [
            .init(id: UUID(), type: .bing, isEnabled: true),
            .init(id: UUID(), type: .native, isEnabled: true),
        ]
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let system = "系统翻译的结果"
        let bing = "必应翻译的结果"
        model.overlayState = .paragraphResult(ParagraphOverlayContent(
            originalText: "First line.\nSecond line.",
            translationState: .ready(system),
            serviceResults: [.init(sourceType: .bing, modelName: nil, state: .ready(bing), isComplete: true)]
        ))
        let host = NSHostingView(rootView: OverlayView(paragraphOverlayMaxSize: CGSize(width: 500, height: 320))
            .environmentObject(model)
            .environment(\.translationPasteboard, pasteboard))
        let panel = NSPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        func visibleTexts(in view: NSView) -> [String] {
            if let text = view as? WordLookupTextView { return [text.string] }
            return view.subviews.flatMap(visibleTexts)
        }
        func clickHeader(trailingOffset: CGFloat) async throws {
            let point = NSPoint(x: panel.frame.width - trailingOffset, y: panel.frame.height - 22)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
                ))
                panel.sendEvent(event)
            }
            await Task.yield()
            panel.setContentSize(host.fittingSize)
            panel.layoutIfNeeded()
        }

        XCTAssertEqual(Set(visibleTexts(in: host)), Set([bing, system]))
        try await clickHeader(trailingOffset: 49)
        XCTAssertEqual(visibleTexts(in: host), [bing])
        // In the unpinned results header the trailing controls are More, Copy
        // and the provider disclosure. Copy moves into each row when expanded.
        try await clickHeader(trailingOffset: 49)
        XCTAssertEqual(pasteboard.string(forType: .string), bing)
        try await clickHeader(trailingOffset: 72)
        XCTAssertEqual(Set(visibleTexts(in: host)), Set([bing, system]))
        try await clickHeader(trailingOffset: 49)
        XCTAssertEqual(visibleTexts(in: host), [bing])
    }

    func testOpeningComparisonResizesTheVisibleWindowToBothShortTranslations() async throws {
        let suite = "SentenceReadingCardTests.\(UUID().uuidString)"
        let model = try makeModel(suite: suite)
        defer { model.dismissOverlay() }
        let savedSize = SentencePopupSize(width: 485, maxHeight: 140)
        model.settings.sentencePopupSize = savedSize
        model.settings.continuousTranslation = false
        model.settings.sentenceTranslationPresentationMode = .overlayPanel
        model.settings.hideOriginalTextInSentenceOverlay = true
        model.settings.sentenceTranslationSources = [
            .init(id: UUID(), type: .native, isEnabled: true),
            .init(id: UUID(), type: .omlx, isEnabled: true),
        ]
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let source = CGRect(x: screen.midX - 240, y: screen.midY, width: 480, height: 46)
        model.setParagraphSourceRegion(source, selectionMode: .cursorParagraph)
        let system = "敌人有元素弱点，使用这些元素的攻击将造成更大的伤害。"
        let omlx = "敌人有元素弱点，使用这些元素攻击会造成额外伤害。"
        var content = ParagraphOverlayContent(
            originalText: "Enemies have elemental weaknesses, and attacks\nwith these elements will deal increased damage.",
            translationState: .ready(system),
            serviceResults: [.init(sourceType: .omlx, modelName: "Local", state: .ready(omlx), duration: 0.7, isComplete: true)],
            sourceLanguageIdentifier: "en", selectedTargetLanguageIdentifier: "zh-Hans"
        )
        model.updateOverlay(state: .paragraphResult(content), anchor: CGPoint(x: source.midX, y: source.midY))
        model.handlePersistentSentenceOverlayRelease()
        XCTAssertTrue(model.isParagraphOverlayPinned)
        let window = try XCTUnwrap(model.overlayWindowController.window)
        let root = try XCTUnwrap(window.contentView)
        func textViews(in view: NSView) -> [WordLookupTextView] {
            if let text = view as? WordLookupTextView { return [text] }
            return view.subviews.flatMap(textViews)
        }
        func waitForLayout(_ settled: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(1)
            while !settled(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        func clickComparison(trailingOffset: CGFloat) throws {
            let point = NSPoint(x: window.frame.width - trailingOffset, y: window.frame.height - 22)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
                ))
                window.sendEvent(event)
            }
        }

        try await waitForLayout { window.isVisible && window.alphaValue == 1 && window.frame.height > savedSize.maxHeight }
        XCTAssertEqual(Set(textViews(in: root).map(\.string)), Set([system, omlx]))
        XCTAssertNil(firstScrollView(in: root))
        try clickComparison(trailingOffset: 73)
        try await waitForLayout { textViews(in: root).count == 1 && window.frame.height < savedSize.maxHeight }
        let collapsedHeight = window.frame.height
        XCTAssertEqual(textViews(in: root).map(\.string), [system])
        // The pinned panel adds a Close button. When expanded, Copy moves to each row.
        try clickComparison(trailingOffset: 96)
        try await waitForLayout {
            let visible = textViews(in: root)
            return visible.count == 2 && firstScrollView(in: root) == nil
                && visible.allSatisfy { root.bounds.contains($0.convert($0.bounds, to: root)) }
        }
        let texts = textViews(in: root)
        let scroll = firstScrollView(in: root)
        let rowFrames = texts.map { $0.convert($0.bounds, to: root) }
        let geometry = "collapsed=\(collapsedHeight), expanded=\(window.frame.height), viewport=\(String(describing: scroll?.documentVisibleRect)), document=\(String(describing: scroll?.documentView?.bounds)), rows=\(rowFrames)"
        let attachment = XCTAttachment(string: geometry)
        attachment.name = "Rendered comparison geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(Set(texts.map(\.string)), Set([system, omlx]), geometry)
        XCTAssertGreaterThan(window.frame.height, collapsedHeight, geometry)
        XCTAssertNil(scroll, geometry)
        XCTAssertTrue(rowFrames.allSatisfy(root.bounds.contains), geometry)
        XCTAssertEqual(window.frame.width, savedSize.width, accuracy: 1)

        // New output from the other provider must still respect the space beside the source.
        content.serviceResults[0].state = .ready(String(repeating: omlx + "\n", count: 100))
        model.updateOverlay(state: .paragraphResult(content))
        let limit = ParagraphOverlayLayout(screenFrame: screen, anchor: .zero, sourceRect: source).maxPanelSize.height
        try await waitForLayout { abs(window.frame.height - limit) <= 1 && firstScrollView(in: root) != nil }
        let longGeometry = "visible=\(window.isVisible), frame=\(window.frame), limit=\(limit), renderedTextLengths=\(textViews(in: root).map { $0.string.count })"
        let scrolling = try XCTUnwrap(firstScrollView(in: root), longGeometry)
        XCTAssertGreaterThan(try XCTUnwrap(scrolling.documentView).bounds.height, scrolling.documentVisibleRect.height)
        XCTAssertEqual(window.frame.height, limit, accuracy: 1)
        XCTAssertFalse(window.frame.intersects(source))
        XCTAssertEqual(model.settings.sentencePopupSize, savedSize)

        try clickComparison(trailingOffset: 73)
        try await waitForLayout { abs(window.frame.height - collapsedHeight) <= 1 && textViews(in: root).count == 1 }
        XCTAssertEqual(window.frame.height, collapsedHeight, accuracy: 1)
        XCTAssertEqual(textViews(in: root).map(\.string), [system])
        XCTAssertNil(firstScrollView(in: root))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let storedSize = defaults.dictionary(forKey: AppSettingKey.sentencePopupSize) as? [String: Double]
        XCTAssertEqual(storedSize, ["width": savedSize.width, "maxHeight": savedSize.maxHeight])

        // A partial provider update in the same lookup must keep the user's choice.
        let updatedSystem = "利用元素弱点可以造成更高伤害。"
        content.translationState = .ready(updatedSystem)
        content.serviceResults[0].state = .ready(omlx)
        content.serviceResults[0].isComplete = false
        model.updateOverlay(state: .paragraphResult(content))
        try await waitForLayout { textViews(in: root).map(\.string) == [updatedSystem] }
        XCTAssertEqual(textViews(in: root).map(\.string), [updatedSystem])

        try clickComparison(trailingOffset: 96)
        try await waitForLayout { window.frame.height > savedSize.maxHeight && firstScrollView(in: root) == nil }
        XCTAssertEqual(Set(textViews(in: root).map(\.string)), Set([updatedSystem, omlx]))
        let expandedHeight = window.frame.height
        XCTAssertGreaterThan(expandedHeight, savedSize.maxHeight)
        func findGrip(in view: NSView) -> SentencePopupResizeHandle.Grip? {
            if let grip = view as? SentencePopupResizeHandle.Grip { return grip }
            return view.subviews.lazy.compactMap { findGrip(in: $0) }.first
        }
        let grip = try XCTUnwrap(findGrip(in: root))
        let onVerticalResize = try XCTUnwrap(grip.onVerticalResize)
        let pointer = window.convertPoint(toScreen: grip.convert(CGPoint(x: grip.bounds.midX, y: grip.bounds.midY), to: nil))
        let controller = model.overlayWindowController
        controller.beginPopupResize(at: pointer)
        controller.resizePopup(
            to: CGPoint(x: pointer.x, y: pointer.y + expandedHeight - savedSize.maxHeight),
            onVerticalResize: onVerticalResize
        )
        // Dragging back to the very same saved limit must still resize the live comparison.
        try await waitForLayout { abs(window.frame.height - savedSize.maxHeight) <= 1 && firstScrollView(in: root) != nil }
        XCTAssertEqual(window.frame.height, savedSize.maxHeight, accuracy: 1)
        XCTAssertNotNil(firstScrollView(in: root))
        controller.endPopupResize()
        try clickComparison(trailingOffset: 73)
        try await waitForLayout { abs(window.frame.height - collapsedHeight) <= 1 }
        try clickComparison(trailingOffset: 96)
        try await waitForLayout { abs(window.frame.height - expandedHeight) <= 1 && firstScrollView(in: root) == nil }
        XCTAssertEqual(window.frame.height, expandedHeight, accuracy: 1)
        XCTAssertNil(firstScrollView(in: root))

        try clickComparison(trailingOffset: 73)
        try await waitForLayout { textViews(in: root).map(\.string) == [updatedSystem] }
        let currentLookup = model.activeLookupID
        let edited = "Use elemental weaknesses to deal more damage."
        model.updateParagraphOriginalText(edited)
        try await waitForLayout { textViews(in: root).contains { $0.string == edited } }
        XCTAssertEqual(Set(textViews(in: root).map(\.string)), Set([edited, updatedSystem]))
        XCTAssertEqual(model.activeLookupID, currentLookup)

        // Retranslate the same text without contacting providers, then reopen the panel
        // after a single-source lookup. Only pressing the disclosure should change the preference.
        let configured = model.settings.sentenceTranslationSources
        content.originalText = edited
        content.isManualInputFallback = true
        content.serviceResults[0].isComplete = true
        for expanded in [false, true] {
            if expanded { try clickComparison(trailingOffset: 96) }
            try await waitForLayout { model.settings.showsAllSentenceTranslations == expanded }
            let previousLookup = model.activeLookupID
            model.settings.sentenceTranslationSources = []
            model.submitParagraphOriginalText()
            XCTAssertNotEqual(model.activeLookupID, previousLookup)
            model.settings.sentenceTranslationSources = configured
            let translated = expanded ? "展开时的新译文" : "收起时的新译文"
            content.translationState = .ready(translated)
            let primary = Set([edited, translated])
            let expected = expanded ? primary.union([omlx]) : primary
            model.updateOverlay(state: .paragraphResult(content))
            try await waitForLayout { Set(textViews(in: root).map(\.string)) == expected }
            XCTAssertEqual(Set(textViews(in: root).map(\.string)), expected)

            model.dismissOverlay()
            var single = content
            single.serviceResults = []
            model.updateOverlay(state: .paragraphResult(single), anchor: source.origin)
            try await waitForLayout { Set(textViews(in: root).map(\.string)) == primary }
            XCTAssertEqual(Set(textViews(in: root).map(\.string)), primary)
            model.dismissOverlay()
            model.updateOverlay(state: .paragraphResult(content), anchor: source.origin)
            model.handlePersistentSentenceOverlayRelease()
            try await waitForLayout { window.alphaValue == 1 && Set(textViews(in: root).map(\.string)) == expected }
            XCTAssertEqual(Set(textViews(in: root).map(\.string)), expected)
            let reloaded = SettingsStore(defaults: defaults, loginItemStatus: false)
            XCTAssertEqual(reloaded.showsAllSentenceTranslations, expanded)
        }
    }

    func testCompactNativeResultSizesForVisibleTextAndFont() throws {
        let model = try makeModel()
        model.settings.hideOriginalTextInSentenceOverlay = true
        var content = ParagraphOverlayContent(
            originalText: String(repeating: "A longer line of game dialogue. ", count: 5),
            translationState: .ready("继续")
        )
        func size() -> CGSize {
            model.overlayState = .paragraphResult(content)
            return NSHostingView(rootView: OverlayView(paragraphOverlayMaxSize: CGSize(width: 800, height: 600))
                .environmentObject(model)).fittingSize
        }
        let short = size()
        XCTAssertLessThan(short.width, 300)
        content.translationState = .ready("这是需要更宽的弹窗才能显示的游戏对话。")
        XCTAssertGreaterThan(size().width, short.width)
        model.settings.sentencePopupFontSize = 24
        let large = size()
        XCTAssertGreaterThan(large.height, short.height)
        model.settings.hideOriginalTextInSentenceOverlay = false
        XCTAssertGreaterThan(size().height, large.height)
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

        let readingWidth = host(width: 800, appearance: .light).fittingSize.width
        for appearance in [ColorScheme.dark, .light] {
            let view = host(width: 800, appearance: appearance)
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.contentView = view
            let size = view.fittingSize
            XCTAssertEqual(size.width, readingWidth, accuracy: 1)
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
        XCTAssertEqual(host(width: 800, appearance: .dark).fittingSize.width, readingWidth, accuracy: 1)
        content.originalText = Array(repeating: source, count: 5).joined(separator: " ")
        XCTAssertEqual(host(width: 800, appearance: .dark).fittingSize.width, 500, accuracy: 1)
        XCTAssertEqual(host(width: 335, appearance: .dark).fittingSize.width, 335, accuracy: 1)
        content.originalText = "Go!"
        let compactWidth = host(width: 800, appearance: .dark).fittingSize.width
        XCTAssertLessThan(compactWidth, readingWidth)
        XCTAssertLessThan(compactWidth, 300)
        model.settings.sentencePopupSize = SentencePopupSize(width: 360, maxHeight: 120)
        let overridden = host(width: 800, appearance: .dark).fittingSize
        XCTAssertEqual(overridden.width, 360, accuracy: 1)
        XCTAssertEqual(overridden.height, 120, accuracy: 1)
        model.settings.sentencePopupSize = nil
        XCTAssertEqual(host(width: 800, appearance: .dark).fittingSize.width, compactWidth, accuracy: 1)
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
        XCTAssertGreaterThan(settledHeights.count, 1)
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
