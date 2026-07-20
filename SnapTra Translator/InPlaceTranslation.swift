import AppKit
import SwiftUI

private final class InPlaceTranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct InPlaceTranslationContent: Equatable {
    var originalText: String
    var translationState: InPlaceTranslationState
    var sourceRect: CGRect
    var sourceLineRects: [CGRect]
    var bodyFontSize: CGFloat
    var style: InPlaceTranslationStyle
}

enum InPlaceTranslationState: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

enum InPlaceTranslationPresentationPolicy {
    static func shouldShowWindow(for state: InPlaceTranslationState) -> Bool {
        switch state {
        case .loading:
            return false
        case .ready, .failed:
            return true
        }
    }
}

struct InPlaceTranslationStyle: Equatable {
    var backgroundColor: NSColor
    var foregroundColor: NSColor
    var borderColor: NSColor
}

enum InPlaceTranslationStyleResolver {
    private static let defaultStyle = InPlaceTranslationStyle(
        backgroundColor: .windowBackgroundColor,
        foregroundColor: .labelColor,
        borderColor: NSColor(calibratedWhite: 0.68, alpha: 1)
    )

    static func resolve(
        captureImage: CGImage?,
        captureRect: CGRect,
        sourceRect: CGRect,
        sourceLineRects: [CGRect]
    ) -> InPlaceTranslationStyle {
        guard let image = captureImage,
              captureRect.width > 0, captureRect.height > 0 else {
            return defaultStyle
        }

        let normalizedX = (sourceRect.minX - captureRect.minX) / captureRect.width
        let normalizedY = (sourceRect.minY - captureRect.minY) / captureRect.height
        let normalizedW = sourceRect.width / captureRect.width
        let normalizedH = sourceRect.height / captureRect.height

        let pixelX = Int(normalizedX * CGFloat(image.width))
        let pixelY = Int(normalizedY * CGFloat(image.height))
        let pixelW = max(1, Int(normalizedW * CGFloat(image.width)))
        let pixelH = max(1, Int(normalizedH * CGFloat(image.height)))

        let clampedX = max(0, min(pixelX, image.width - 1))
        let clampedY = max(0, min(pixelY, image.height - 1))
        let clampedW = max(1, min(pixelW, image.width - clampedX))
        let clampedH = max(1, min(pixelH, image.height - clampedY))

        guard let averageColor = Self.averageColor(
            in: CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH),
            image: image
        ) else {
            return defaultStyle
        }

        let luminance = Self.relativeLuminance(for: averageColor)
        let foregroundColor: NSColor = luminance > 0.5
            ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor(calibratedWhite: 0.96, alpha: 1)

        let backgroundColor: NSColor = luminance > 0.5
            ? NSColor(calibratedWhite: 0.98, alpha: 1)
            : NSColor(calibratedWhite: 0.08, alpha: 1)
        let borderColor: NSColor = luminance > 0.5
            ? NSColor(calibratedWhite: 0.68, alpha: 1)
            : NSColor(calibratedWhite: 0.34, alpha: 1)

        return InPlaceTranslationStyle(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            borderColor: borderColor
        )
    }

    private static func averageColor(in pixelRect: CGRect, image: CGImage) -> NSColor? {
        let sampleW = min(16, Int(pixelRect.width))
        let sampleH = min(16, Int(pixelRect.height))
        guard sampleW > 0, sampleH > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: sampleW * sampleH * 4)

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        let count = Double(sampleW * sampleH)

        for row in 0..<sampleH {
            for col in 0..<sampleW {
                let offset = (row * sampleW + col) * 4
                totalR += Double(pixels[offset]) / 255.0
                totalG += Double(pixels[offset + 1]) / 255.0
                totalB += Double(pixels[offset + 2]) / 255.0
            }
        }

        return NSColor(
            calibratedRed: CGFloat(totalR / count),
            green: CGFloat(totalG / count),
            blue: CGFloat(totalB / count),
            alpha: 1
        )
    }

    private static func relativeLuminance(for color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}

struct InPlaceTranslationTextFrame: Equatable {
    var origin: CGPoint
    var size: CGSize
}

struct InPlaceTranslationLayoutResult: Equatable {
    let fontSize: CGFloat
    let padding: CGFloat
    let cornerRadius: CGFloat
    let textFrame: InPlaceTranslationTextFrame
}

enum InPlaceTranslationLayout {
    static func resolve(
        sourceRect: CGRect,
        preferredFontSize: CGFloat,
        translatedText: String
    ) -> InPlaceTranslationLayoutResult {
        resolve(
            sourceRect: sourceRect,
            sourceLineRects: [],
            preferredFontSize: preferredFontSize,
            translatedText: translatedText
        )
    }

    static func resolve(
        sourceRect: CGRect,
        sourceLineRects: [CGRect],
        preferredFontSize: CGFloat,
        translatedText: String
    ) -> InPlaceTranslationLayoutResult {
        let width = max(sourceRect.width, 1)
        let height = max(sourceRect.height, 1)
        let area = max(width * height, 1)
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

        let lineInset = max(2, min(6, height * 0.06))
        let localLines = sourceLineRects
            .map { CGRect(x: $0.minX - sourceRect.minX, y: $0.minY - sourceRect.minY, width: $0.width, height: $0.height) }
            .filter { $0.width > 1 && $0.height > 1 }
        let anchor = localLines.sorted { $0.minY < $1.minY }.first

        let maxTextWidth = max(20, width - 2 * lineInset)
        let maxTextHeight = max(16, height - 2 * lineInset)
        let clampedX = max(lineInset, min((anchor?.minX ?? 0) + lineInset, width - lineInset - maxTextWidth / 2))
        let clampedY = max(lineInset, min((anchor?.minY ?? 0) + lineInset, height - lineInset - maxTextHeight / 2))
        let textWidth = max(20, width - clampedX - lineInset)
        let textHeight = max(16, height - clampedY - lineInset)

        return InPlaceTranslationLayoutResult(
            fontSize: fontSize,
            padding: padding,
            cornerRadius: cornerRadius,
            textFrame: InPlaceTranslationTextFrame(
                origin: CGPoint(x: clampedX, y: clampedY),
                size: CGSize(width: textWidth, height: textHeight)
            )
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
            sourceLineRects: content.sourceLineRects,
            preferredFontSize: content.bodyFontSize,
            translatedText: displayText
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(Color(nsColor: content.style.backgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: content.style.borderColor).opacity(0.55), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 1)

            InPlaceSelectableTextView(
                text: displayText,
                font: .systemFont(ofSize: layout.fontSize, weight: .semibold),
                textColor: content.style.foregroundColor
            )
            .frame(
                width: layout.textFrame.size.width,
                height: layout.textFrame.size.height,
                alignment: .topLeading
            )
            .position(
                x: layout.textFrame.origin.x + layout.textFrame.size.width / 2,
                y: layout.textFrame.origin.y + layout.textFrame.size.height / 2
            )
        }
    }
}

struct InPlaceImageTranslationContent: Equatable {
    var state: InPlaceImageTranslationState
    var sourceRect: CGRect
}

enum InPlaceImageTranslationState: Equatable {
    case loading
    case ready(Data)
    case failed(String)
}

enum InPlaceImageTranslationLoadingAppearance {
    static let backgroundOpacity: Double = 0
    static let beamHaloPeakOpacity: Double = 0.34
    static let beamCoreOpacity: Double = 0.68
    static let cornerStrokeOpacity: Double = 0.82
    static let scanDuration: TimeInterval = 1.4
    static let beamHaloHalf: CGFloat = 28
    static let beamCoreWidth: CGFloat = 2.5

    static func beamCenterX(elapsed: TimeInterval, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }

        let travel = width + beamHaloHalf * 2
        let period = scanDuration * 2
        let t = elapsed.truncatingRemainder(dividingBy: period) / period
        let raw = t < 0.5 ? t * 2 : (1 - t) * 2
        let eased = raw < 0.5
            ? 2 * raw * raw
            : 1 - pow(-2 * raw + 2, 2) / 2

        return -beamHaloHalf + eased * travel
    }

    static func cornerLength(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) * 0.22, 22)
    }
}

struct InPlaceImageTranslationView: View {
    let content: InPlaceImageTranslationContent

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch content.state {
                case .loading:
                    InPlaceImageTranslationLoadingView()
                case .ready(let imageData):
                    if let image = NSImage(data: imageData) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else {
                        fallbackContent(message: L("Image translation failed"), size: proxy.size)
                    }
                case .failed(let message):
                    fallbackContent(message: message, size: proxy.size)
                }
            }
        }
    }

    private func fallbackContent(message: String, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size.height < 32 ? 4 : 7, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: size.height < 32 ? 4 : 7, style: .continuous)
                        .strokeBorder(Color(nsColor: NSColor(calibratedWhite: 0.68, alpha: 1)).opacity(0.55), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 1)

            Text(message)
                .font(.system(size: max(11, min(15, size.height * 0.28)), weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(size.height < 32 ? 4 : 8)
        }
    }
}

private struct InPlaceImageTranslationLoadingView: View {
    private let accentColor = Color(red: 0.18, green: 0.88, blue: 0.42)

    @State private var startDate: Date = .now

    var body: some View {
        GeometryReader { proxy in
            let cornerRadius: CGFloat = proxy.size.height < 32 ? 4 : 7

            TimelineView(.animation) { timeline in
                Canvas { ctx, canvasSize in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    let centerX = InPlaceImageTranslationLoadingAppearance.beamCenterX(
                        elapsed: elapsed,
                        width: canvasSize.width
                    )

                    drawBeam(ctx: ctx, canvasSize: canvasSize, centerX: centerX)
                    drawCorners(ctx: ctx, canvasSize: canvasSize)
                }
            }
            .background(Color.clear.opacity(InPlaceImageTranslationLoadingAppearance.backgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel(Text(L("Translating")))
            .onAppear {
                startDate = .now
            }
        }
    }

    private func drawBeam(ctx: GraphicsContext, canvasSize: CGSize, centerX: CGFloat) {
        let totalHalf = InPlaceImageTranslationLoadingAppearance.beamHaloHalf
            + InPlaceImageTranslationLoadingAppearance.beamCoreWidth / 2
        let haloLeft = centerX - totalHalf
        let haloRight = centerX + totalHalf
        let clampedLeft = max(0, haloLeft)
        let clampedRight = min(canvasSize.width, haloRight)

        if clampedRight > clampedLeft {
            let haloRect = CGRect(
                x: clampedLeft,
                y: 0,
                width: clampedRight - clampedLeft,
                height: canvasSize.height
            )
            let haloGradient = Gradient(stops: [
                .init(color: accentColor.opacity(0), location: 0),
                .init(
                    color: accentColor.opacity(InPlaceImageTranslationLoadingAppearance.beamHaloPeakOpacity * 0.36),
                    location: 0.25
                ),
                .init(
                    color: accentColor.opacity(InPlaceImageTranslationLoadingAppearance.beamHaloPeakOpacity),
                    location: 0.48
                ),
                .init(
                    color: accentColor.opacity(InPlaceImageTranslationLoadingAppearance.beamHaloPeakOpacity),
                    location: 0.52
                ),
                .init(
                    color: accentColor.opacity(InPlaceImageTranslationLoadingAppearance.beamHaloPeakOpacity * 0.36),
                    location: 0.75
                ),
                .init(color: accentColor.opacity(0), location: 1),
            ])

            ctx.fill(
                Path(haloRect),
                with: .linearGradient(
                    haloGradient,
                    startPoint: CGPoint(x: haloLeft, y: canvasSize.height / 2),
                    endPoint: CGPoint(x: haloRight, y: canvasSize.height / 2)
                )
            )
        }

        let coreLeft = max(0, centerX - InPlaceImageTranslationLoadingAppearance.beamCoreWidth / 2)
        let coreRight = min(canvasSize.width, centerX + InPlaceImageTranslationLoadingAppearance.beamCoreWidth / 2)
        guard coreRight > coreLeft else { return }

        let coreRect = CGRect(
            x: coreLeft,
            y: 0,
            width: coreRight - coreLeft,
            height: canvasSize.height
        )
        ctx.fill(
            Path(coreRect),
            with: .color(accentColor.opacity(InPlaceImageTranslationLoadingAppearance.beamCoreOpacity))
        )
    }

    private func drawCorners(ctx: GraphicsContext, canvasSize: CGSize) {
        let size = CGSize(width: canvasSize.width, height: canvasSize.height)
        let cornerLength = InPlaceImageTranslationLoadingAppearance.cornerLength(for: size)
        guard cornerLength > 0 else { return }

        let rect = CGRect(origin: .zero, size: size)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))

        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))

        ctx.stroke(
            path,
            with: .color(accentColor.opacity(InPlaceImageTranslationLoadingAppearance.cornerStrokeOpacity)),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - Selectable Text View

private struct InPlaceSelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        applyContent(textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        applyContent(textView)
    }

    private func applyContent(_ textView: NSTextView) {
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: textColor]
            )
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

@MainActor
final class InPlaceTranslationWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init() {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        let panel = InPlaceTranslationPanel(
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
        guard InPlaceTranslationPresentationPolicy.shouldShowWindow(for: content.translationState) else {
            hide()
            return
        }

        hostingView.rootView = AnyView(InPlaceTranslationView(content: content))
        window.setFrame(content.sourceRect, display: true)
        window.orderFrontRegardless()
        if case .ready = content.translationState {
            setInteractive(true)
        } else {
            setInteractive(false)
        }
    }

    func hide() {
        setInteractive(false)
        hostingView.rootView = AnyView(EmptyView())
        window?.orderOut(nil)
    }

    func setInteractive(_ interactive: Bool) {
        guard let window else { return }
        window.ignoresMouseEvents = !interactive
        if interactive {
            window.makeKey()
        }
    }

    var visibleFrame: CGRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }
}

@MainActor
final class InPlaceImageTranslationWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init() {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        let panel = InPlaceTranslationPanel(
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

    func show(content: InPlaceImageTranslationContent) {
        guard let window else { return }
        hostingView.rootView = AnyView(InPlaceImageTranslationView(content: content))
        window.setFrame(content.sourceRect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        hostingView.rootView = AnyView(EmptyView())
        window?.orderOut(nil)
    }

    var visibleFrame: CGRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }
}
