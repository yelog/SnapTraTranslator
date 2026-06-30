import AppKit
import SwiftUI

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

struct InPlaceTranslationStyle: Equatable {
    var backgroundColor: NSColor
    var foregroundColor: NSColor
    var backgroundOpacity: CGFloat
    var materialOpacity: CGFloat
}

enum InPlaceTranslationStyleResolver {
    private static let defaultStyle = InPlaceTranslationStyle(
        backgroundColor: .windowBackgroundColor,
        foregroundColor: .labelColor,
        backgroundOpacity: 0.72,
        materialOpacity: 0.22
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

        return InPlaceTranslationStyle(
            backgroundColor: averageColor,
            foregroundColor: foregroundColor,
            backgroundOpacity: 0.72,
            materialOpacity: 0.22
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
                .fill(Color(nsColor: content.style.backgroundColor).opacity(content.style.backgroundOpacity))
                .background(.regularMaterial.opacity(content.style.materialOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: content.style.foregroundColor).opacity(0.12), lineWidth: 0.5)
                )

            Text(displayText)
                .font(.system(size: layout.fontSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: content.style.foregroundColor))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .minimumScaleFactor(0.55)
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
