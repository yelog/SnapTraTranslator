import AppKit
import SwiftUI

struct InPlaceTranslationContent: Equatable {
    var originalText: String
    var translationState: InPlaceTranslationState
    var sourceRect: CGRect
    var sourceLineRects: [CGRect]
    var bodyFontSize: CGFloat
}

enum InPlaceTranslationState: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

struct InPlaceTranslationLayoutResult: Equatable {
    let fontSize: CGFloat
    let padding: CGFloat
    let cornerRadius: CGFloat
}

enum InPlaceTranslationLayout {
    static func resolve(
        sourceRect: CGRect,
        preferredFontSize: CGFloat,
        translatedText: String
    ) -> InPlaceTranslationLayoutResult {
        let height = max(sourceRect.height, 1)
        let area = max(sourceRect.width * sourceRect.height, 1)
        let padding: CGFloat = height < 32 ? 4 : 8
        let cornerRadius: CGFloat = height < 32 ? 4 : 7

        let lengthPenalty: CGFloat
        if translatedText.count > 120 {
            lengthPenalty = 0.78
        } else if translatedText.count > 60 {
            lengthPenalty = 0.88
        } else {
            lengthPenalty = 1
        }

        let sizeByHeight = max(10, min(preferredFontSize, height * 0.48))
        let sizeByArea = area < 8_000 ? min(sizeByHeight, 13) : sizeByHeight
        let fontSize = max(10, min(22, sizeByArea * lengthPenalty))

        return InPlaceTranslationLayoutResult(
            fontSize: fontSize,
            padding: padding,
            cornerRadius: cornerRadius
        )
    }
}

struct InPlaceTranslationView: View {
    let content: InPlaceTranslationContent

    private var displayText: String {
        switch content.translationState {
        case .loading:
            return L("Translating")
        case .ready(let text):
            return text
        case .failed(let message):
            return L(message)
        }
    }

    private var layout: InPlaceTranslationLayoutResult {
        InPlaceTranslationLayout.resolve(
            sourceRect: content.sourceRect,
            preferredFontSize: content.bodyFontSize,
            translatedText: displayText
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )

            Text(displayText)
                .font(.system(size: layout.fontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .minimumScaleFactor(0.55)
                .padding(layout.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

@MainActor
final class InPlaceTranslationWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init() {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
        CaptureExclusionRegistry.shared.register(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(content: InPlaceTranslationContent) {
        guard let window else { return }
        hostingView.rootView = AnyView(InPlaceTranslationView(content: content))
        window.setFrame(content.sourceRect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        hostingView.rootView = AnyView(EmptyView())
        window?.orderOut(nil)
    }
}
