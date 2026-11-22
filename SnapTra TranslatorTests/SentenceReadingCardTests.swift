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
    }

    private func makeModel() throws -> AppModel {
        let suite = "SentenceReadingCardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)
        let container = try ModelContainer(for: WordRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return AppModel(settings: settings, modelContext: container.mainContext)
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
