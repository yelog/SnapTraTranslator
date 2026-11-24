import AppKit
import Combine
import QuartzCore
import SwiftUI

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class ManualRegionSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Debug OCR Border View

struct DebugOCRBorderView: View {
    var wordBoxes: [CGRect]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .stroke(Color.red, lineWidth: 3)
                    .background(Color.clear)

                ForEach(Array(wordBoxes.enumerated()), id: \.offset) { _, box in
                    let converted = convertNormalizedBox(box, in: geometry.size)
                    Rectangle()
                        .stroke(Color.green, lineWidth: 1.5)
                        .frame(width: converted.width, height: converted.height)
                        .position(x: converted.midX, y: converted.midY)
                }
            }
        }
    }

    private func convertNormalizedBox(_ box: CGRect, in size: CGSize) -> CGRect {
        let x = box.origin.x * size.width
        let y = (1 - box.origin.y - box.height) * size.height
        let width = box.width * size.width
        let height = box.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Debug Overlay Window Controller

final class DebugOverlayWindowController: NSWindowController {
    private var hostingView: NSHostingView<AnyView>

    override init(window: NSWindow?) {
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
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
        CaptureExclusionRegistry.shared.register(panel)
    }

    convenience init() {
        self.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(at rect: CGRect, wordBoxes: [CGRect] = []) {
        guard let window else { return }
        hostingView.rootView = AnyView(DebugOCRBorderView(wordBoxes: wordBoxes))
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        hostingView.rootView = AnyView(EmptyView())
        window?.orderOut(nil)
    }
}

// MARK: - Manual OCR Region Selection

enum ManualRegionSelectionPresentationPolicy {
    static let activatesApplication = false
    static let acceptsFirstMouse = true
}

private final class ManualRegionSelectionView: NSView {
    var onComplete: (CGRect) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private let minimumSelectionSize = CGSize(width: 12, height: 12)

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        ManualRegionSelectionPresentationPolicy.acceptsFirstMouse
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        if let selectionRect {
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            selectionRect.fill()

            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
            path.lineWidth = 2
            path.stroke()
        }

        drawHint()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragCurrent = event.locationInWindow
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = event.locationInWindow
        guard let selectionRect,
              selectionRect.width >= minimumSelectionSize.width,
              selectionRect.height >= minimumSelectionSize.height,
              let window else {
            resetSelection()
            return
        }

        let screenRect = window.convertToScreen(selectionRect)
        resetSelection()
        onComplete(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            resetSelection()
            onCancel()
            return
        }
        super.keyDown(with: event)
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )
    }

    private func resetSelection() {
        dragStart = nil
        dragCurrent = nil
        needsDisplay = true
    }

    private func drawHint() {
        let text = L("Drag to select a region to translate · Esc to cancel")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .backgroundColor: NSColor.black.withAlphaComponent(0.35),
        ]
        let attributed = NSAttributedString(string: "  \(text)  ", attributes: attributes)
        let size = attributed.size()
        let rect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height - 28,
            width: size.width,
            height: size.height
        )
        attributed.draw(in: rect)
    }
}

final class ManualRegionSelectionWindowController {
    private var panels: [NSPanel] = []
    private var didFinish = false

    func begin(onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        hide()
        didFinish = false

        if ManualRegionSelectionPresentationPolicy.activatesApplication {
            NSApp.activate(ignoringOtherApps: true)
        }

        for screen in NSScreen.screens {
            let selectionView = ManualRegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            selectionView.autoresizingMask = [.width, .height]
            let panel = ManualRegionSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = selectionView
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.worksWhenModal = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true

            selectionView.onComplete = { [weak self] rect in
                guard let self, !self.didFinish else { return }
                self.didFinish = true
                self.hide()
                onComplete(rect)
            }
            selectionView.onCancel = { [weak self] in
                guard let self, !self.didFinish else { return }
                self.didFinish = true
                self.hide()
                onCancel()
            }

            CaptureExclusionRegistry.shared.register(panel)
            panels.append(panel)
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(selectionView)
            selectionView.needsDisplay = true
            panel.displayIfNeeded()
        }
    }

    func hide() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }
}

// MARK: - Paragraph Highlight View Model

@MainActor
final class ParagraphHighlightViewModel: ObservableObject {
    @Published var isActive = false
}

enum ParagraphHighlightResizeCorner: CaseIterable, Equatable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var cursor: NSCursor {
        ParagraphHighlightResizeCursorFactory.cursor(for: self)
    }
}

struct ParagraphHighlightCornerFeedback: Equatable {
    let lineWidth: CGFloat
    let opacity: Double
    let showsGrip: Bool
    let gripDiameter: CGFloat

    nonisolated static func resolve(
        corner: ParagraphHighlightResizeCorner,
        hoveredCorner: ParagraphHighlightResizeCorner?,
        activeCorner: ParagraphHighlightResizeCorner?
    ) -> ParagraphHighlightCornerFeedback {
        if activeCorner == corner {
            return ParagraphHighlightCornerFeedback(
                lineWidth: 4,
                opacity: 1,
                showsGrip: true,
                gripDiameter: 7
            )
        }

        if hoveredCorner == corner {
            return ParagraphHighlightCornerFeedback(
                lineWidth: 3.5,
                opacity: 1,
                showsGrip: true,
                gripDiameter: 6
            )
        }

        return ParagraphHighlightCornerFeedback(
            lineWidth: 2.5,
            opacity: 0.85,
            showsGrip: false,
            gripDiameter: 0
        )
    }
}

enum ParagraphHighlightResizeHitTesting {
    nonisolated static func corner(
        at point: CGPoint,
        in size: CGSize,
        handleSize: CGFloat
    ) -> ParagraphHighlightResizeCorner? {
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.contains(point) else { return nil }

        var nearestCorner: ParagraphHighlightResizeCorner?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for corner in ParagraphHighlightResizeCorner.allCases {
            guard handleRect(for: corner, in: size, handleSize: handleSize).contains(point) else {
                continue
            }

            let center = handleCenter(for: corner, in: size)
            let distance = pow(point.x - center.x, 2) + pow(point.y - center.y, 2)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestCorner = corner
            }
        }

        return nearestCorner
    }

    nonisolated static func handleRect(
        for corner: ParagraphHighlightResizeCorner,
        in size: CGSize,
        handleSize: CGFloat
    ) -> CGRect {
        guard size.width > 0, size.height > 0, handleSize > 0 else { return .zero }

        let width = min(handleSize, size.width)
        let height = min(handleSize, size.height)

        switch corner {
        case .topLeft:
            return CGRect(x: 0, y: 0, width: width, height: height)
        case .topRight:
            return CGRect(x: size.width - width, y: 0, width: width, height: height)
        case .bottomLeft:
            return CGRect(x: 0, y: size.height - height, width: width, height: height)
        case .bottomRight:
            return CGRect(x: size.width - width, y: size.height - height, width: width, height: height)
        }
    }

    nonisolated private static func handleCenter(
        for corner: ParagraphHighlightResizeCorner,
        in size: CGSize
    ) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: 0, y: 0)
        case .topRight:
            return CGPoint(x: size.width, y: 0)
        case .bottomLeft:
            return CGPoint(x: 0, y: size.height)
        case .bottomRight:
            return CGPoint(x: size.width, y: size.height)
        }
    }
}

private enum ParagraphHighlightResizeCursorFactory {
    private static let topLeftBottomRightCursor = makeCursor(
        start: CGPoint(x: 8, y: 24),
        end: CGPoint(x: 24, y: 8)
    )
    private static let topRightBottomLeftCursor = makeCursor(
        start: CGPoint(x: 24, y: 24),
        end: CGPoint(x: 8, y: 8)
    )

    static func cursor(for corner: ParagraphHighlightResizeCorner) -> NSCursor {
        switch corner {
        case .topLeft, .bottomRight:
            return topLeftBottomRightCursor
        case .topRight, .bottomLeft:
            return topRightBottomLeftCursor
        }
    }

    private static func makeCursor(start: CGPoint, end: CGPoint) -> NSCursor {
        let imageSize = CGSize(width: 32, height: 32)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        drawCursorPath(start: start, end: end, color: .white, lineWidth: 5.5)
        drawCursorPath(start: start, end: end, color: .black, lineWidth: 2.4)
        image.unlockFocus()

        return NSCursor(image: image, hotSpot: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2))
    }

    private static func drawCursorPath(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = cursorPath(start: start, end: end)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }

    private static func cursorPath(start: CGPoint, end: CGPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        appendArrowhead(to: start, from: end, path: path)
        appendArrowhead(to: end, from: start, path: path)
        return path
    }

    private static func appendArrowhead(to tip: CGPoint, from body: CGPoint, path: NSBezierPath) {
        let dx = tip.x - body.x
        let dy = tip.y - body.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }

        let unit = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let base = CGPoint(x: tip.x - unit.x * 7, y: tip.y - unit.y * 7)
        let first = CGPoint(x: base.x + normal.x * 4.5, y: base.y + normal.y * 4.5)
        let second = CGPoint(x: base.x - normal.x * 4.5, y: base.y - normal.y * 4.5)

        path.move(to: first)
        path.line(to: tip)
        path.line(to: second)
    }
}

enum ParagraphHighlightResizeGeometry {
    nonisolated static func resizedFrame(
        from frame: CGRect,
        corner: ParagraphHighlightResizeCorner,
        screenDelta: CGSize,
        minimumSize: CGSize,
        screenFrame: CGRect?
    ) -> CGRect {
        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY

        switch corner {
        case .topLeft:
            minX += screenDelta.width
            maxY += screenDelta.height
        case .topRight:
            maxX += screenDelta.width
            maxY += screenDelta.height
        case .bottomLeft:
            minX += screenDelta.width
            minY += screenDelta.height
        case .bottomRight:
            maxX += screenDelta.width
            minY += screenDelta.height
        }

        if maxX - minX < minimumSize.width {
            switch corner {
            case .topLeft, .bottomLeft:
                minX = maxX - minimumSize.width
            case .topRight, .bottomRight:
                maxX = minX + minimumSize.width
            }
        }

        if maxY - minY < minimumSize.height {
            switch corner {
            case .topLeft, .topRight:
                maxY = minY + minimumSize.height
            case .bottomLeft, .bottomRight:
                minY = maxY - minimumSize.height
            }
        }

        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let screenFrame else { return rect }
        return clamp(rect, to: screenFrame, minimumSize: minimumSize)
    }

    nonisolated private static func clamp(
        _ rect: CGRect,
        to bounds: CGRect,
        minimumSize: CGSize
    ) -> CGRect {
        let width = min(max(rect.width, minimumSize.width), bounds.width)
        let height = min(max(rect.height, minimumSize.height), bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Paragraph Highlight View

private struct ParagraphHighlightView: View {
    @ObservedObject var model: ParagraphHighlightViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onResizeChanged: (ParagraphHighlightResizeCorner, CGPoint) -> Void
    var onResizeEnded: (ParagraphHighlightResizeCorner, CGPoint) -> Void
    private let accentColor = Color(red: 0.18, green: 0.88, blue: 0.42)
    private let handleSize: CGFloat = 36
    /// Half-width of the soft gradient halo on each side of the beam core
    private let beamHaloHalf: CGFloat = 28
    /// Width of the hard bright core line
    private let beamCoreWidth: CGFloat = 2.5
    /// Single-pass duration in seconds (left→right or right→left)
    private let scanDuration: TimeInterval = 1.4

    @State private var appeared = false
    @State private var startDate: Date = .now
    @State private var hoveredCorner: ParagraphHighlightResizeCorner?
    @State private var activeResizeCorner: ParagraphHighlightResizeCorner?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cornerLength = min(min(size.width, size.height) * 0.22, 22)

            ZStack {
                // Layer 1 — ambient fill
                Rectangle()
                    .fill(accentColor.opacity(0.05))

                // Layer 2 — scan beam via TimelineView, only when active
                if model.isActive && !reduceMotion {
                    TimelineView(.animation) { timeline in
                        Canvas { ctx, canvasSize in
                            let elapsed = timeline.date.timeIntervalSince(startDate)
                            let centerX = beamCenterX(elapsed: elapsed, width: canvasSize.width)
                            drawBeam(ctx: ctx, canvasSize: canvasSize, centerX: centerX)
                        }
                    }
                }

                // Layer 3 — corner brackets
                ForEach(ParagraphHighlightResizeCorner.allCases, id: \.self) { corner in
                    cornerFeedback(for: corner, in: size, cornerLength: cornerLength)
                }

                ParagraphHighlightResizeInteractionView(
                    handleSize: handleSize,
                    onHoverChanged: { corner in
                        hoveredCorner = corner
                    },
                    onActiveCornerChanged: { corner in
                        activeResizeCorner = corner
                    },
                    onResizeChanged: onResizeChanged,
                    onResizeEnded: onResizeEnded
                )
                .frame(width: size.width, height: size.height)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
            .onAppear {
                startDate = .now
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    appeared = true
                }
            }
            .onChange(of: model.isActive) { _, isActive in
                if isActive {
                    startDate = .now
                }
            }
            .animation(.easeOut(duration: 0.12), value: hoveredCorner)
            .animation(.easeOut(duration: 0.12), value: activeResizeCorner)
        }
    }

    // MARK: - Beam position

    /// Returns beam center x for the given elapsed time using a ping-pong easeInOut curve.
    private func beamCenterX(elapsed: TimeInterval, width: CGFloat) -> CGFloat {
        // Travel range: from -halo to width+halo
        let travel = width + beamHaloHalf * 2
        let period = scanDuration * 2          // full round-trip
        let t = elapsed.truncatingRemainder(dividingBy: period) / period  // 0…1 over one round-trip
        // ping-pong: 0→1 then 1→0
        let raw = t < 0.5 ? t * 2 : (1 - t) * 2
        // easeInOut
        let eased = raw < 0.5
            ? 2 * raw * raw
            : 1 - pow(-2 * raw + 2, 2) / 2
        return -beamHaloHalf + eased * travel
    }

    // MARK: - Beam drawing

    private func drawBeam(ctx: GraphicsContext, canvasSize: CGSize, centerX: CGFloat) {
        let totalHalf = beamHaloHalf + beamCoreWidth / 2

        // --- Soft halo gradient ---
        let haloLeft  = centerX - totalHalf
        let haloRight = centerX + totalHalf
        let clampedLeft  = max(0, haloLeft)
        let clampedRight = min(canvasSize.width, haloRight)
        if clampedRight > clampedLeft {
            let haloRect = CGRect(x: clampedLeft, y: 0,
                                  width: clampedRight - clampedLeft,
                                  height: canvasSize.height)
            let haloGradient = Gradient(stops: [
                .init(color: accentColor.opacity(0),    location: 0),
                .init(color: accentColor.opacity(0.18), location: 0.35),
                .init(color: accentColor.opacity(0.55), location: 0.48),
                .init(color: accentColor.opacity(0.55), location: 0.52),
                .init(color: accentColor.opacity(0.18), location: 0.65),
                .init(color: accentColor.opacity(0),    location: 1),
            ])
            ctx.fill(
                Path(haloRect),
                with: .linearGradient(
                    haloGradient,
                    startPoint: CGPoint(x: haloLeft,  y: canvasSize.height / 2),
                    endPoint:   CGPoint(x: haloRight, y: canvasSize.height / 2)
                )
            )
        }

        // --- Hard bright core ---
        let coreLeft  = max(0, centerX - beamCoreWidth / 2)
        let coreRight = min(canvasSize.width, centerX + beamCoreWidth / 2)
        if coreRight > coreLeft {
            let coreRect = CGRect(x: coreLeft, y: 0,
                                  width: coreRight - coreLeft,
                                  height: canvasSize.height)
            ctx.fill(Path(coreRect), with: .color(accentColor.opacity(0.9)))
        }
    }

    // MARK: - Corner brackets

    @ViewBuilder
    private func cornerFeedback(
        for corner: ParagraphHighlightResizeCorner,
        in size: CGSize,
        cornerLength: CGFloat
    ) -> some View {
        let feedback = ParagraphHighlightCornerFeedback.resolve(
            corner: corner,
            hoveredCorner: hoveredCorner,
            activeCorner: activeResizeCorner
        )

        cornerBracket(for: corner, size: size, cornerLength: cornerLength)
            .stroke(
                accentColor.opacity(feedback.opacity),
                style: StrokeStyle(lineWidth: feedback.lineWidth, lineCap: .round, lineJoin: .round)
            )

        if feedback.showsGrip {
            Circle()
                .fill(accentColor.opacity(feedback.opacity))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
                .frame(width: feedback.gripDiameter, height: feedback.gripDiameter)
                .position(gripPosition(for: corner, in: size))
        }
    }

    private func cornerBracket(for corner: ParagraphHighlightResizeCorner, size: CGSize, cornerLength: CGFloat) -> Path {
        Path { path in
            let rect = CGRect(origin: .zero, size: size)

            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
            case .topRight:
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
            case .bottomLeft:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
            case .bottomRight:
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
            }
        }
    }

    private func gripPosition(for corner: ParagraphHighlightResizeCorner, in size: CGSize) -> CGPoint {
        let inset: CGFloat = 6
        switch corner {
        case .topLeft:
            return CGPoint(x: inset, y: inset)
        case .topRight:
            return CGPoint(x: size.width - inset, y: inset)
        case .bottomLeft:
            return CGPoint(x: inset, y: size.height - inset)
        case .bottomRight:
            return CGPoint(x: size.width - inset, y: size.height - inset)
        }
    }
}

private struct ParagraphHighlightResizeInteractionView: NSViewRepresentable {
    let handleSize: CGFloat
    var onHoverChanged: (ParagraphHighlightResizeCorner?) -> Void
    var onActiveCornerChanged: (ParagraphHighlightResizeCorner?) -> Void
    var onResizeChanged: (ParagraphHighlightResizeCorner, CGPoint) -> Void
    var onResizeEnded: (ParagraphHighlightResizeCorner, CGPoint) -> Void

    func makeNSView(context: Context) -> ParagraphHighlightResizeInteractionNSView {
        let view = ParagraphHighlightResizeInteractionNSView()
        view.update(
            handleSize: handleSize,
            onHoverChanged: onHoverChanged,
            onActiveCornerChanged: onActiveCornerChanged,
            onResizeChanged: onResizeChanged,
            onResizeEnded: onResizeEnded
        )
        return view
    }

    func updateNSView(_ nsView: ParagraphHighlightResizeInteractionNSView, context: Context) {
        nsView.update(
            handleSize: handleSize,
            onHoverChanged: onHoverChanged,
            onActiveCornerChanged: onActiveCornerChanged,
            onResizeChanged: onResizeChanged,
            onResizeEnded: onResizeEnded
        )
    }
}

private final class ParagraphHighlightResizeInteractionNSView: NSView {
    private var handleSize: CGFloat = 36
    private var trackingArea: NSTrackingArea?
    private var hoveredCorner: ParagraphHighlightResizeCorner?
    private var activeCorner: ParagraphHighlightResizeCorner?
    private var onHoverChanged: (ParagraphHighlightResizeCorner?) -> Void = { _ in }
    private var onActiveCornerChanged: (ParagraphHighlightResizeCorner?) -> Void = { _ in }
    private var onResizeChanged: (ParagraphHighlightResizeCorner, CGPoint) -> Void = { _, _ in }
    private var onResizeEnded: (ParagraphHighlightResizeCorner, CGPoint) -> Void = { _, _ in }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard corner(at: point) != nil else { return nil }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .cursorUpdate,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved,
        ]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        invalidateCursorRects()
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        for corner in ParagraphHighlightResizeCorner.allCases {
            addCursorRect(
                ParagraphHighlightResizeHitTesting.handleRect(
                    for: corner,
                    in: bounds.size,
                    handleSize: handleSize
                ),
                cursor: corner.cursor
            )
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        invalidateCursorRects()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateCursorRects()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredCorner(nil)
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let corner = corner(for: event) else {
            NSCursor.arrow.set()
            return
        }
        corner.cursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let corner = corner(for: event) else {
            super.mouseDown(with: event)
            return
        }

        activeCorner = corner
        onActiveCornerChanged(corner)
        setHoveredCorner(corner)
        corner.cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeCorner else {
            super.mouseDragged(with: event)
            return
        }

        activeCorner.cursor.set()
        onResizeChanged(activeCorner, NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard let activeCorner else {
            super.mouseUp(with: event)
            return
        }

        self.activeCorner = nil
        onActiveCornerChanged(nil)
        onResizeEnded(activeCorner, NSEvent.mouseLocation)
        updateHover(with: event)
    }

    func update(
        handleSize: CGFloat,
        onHoverChanged: @escaping (ParagraphHighlightResizeCorner?) -> Void,
        onActiveCornerChanged: @escaping (ParagraphHighlightResizeCorner?) -> Void,
        onResizeChanged: @escaping (ParagraphHighlightResizeCorner, CGPoint) -> Void,
        onResizeEnded: @escaping (ParagraphHighlightResizeCorner, CGPoint) -> Void
    ) {
        self.handleSize = handleSize
        self.onHoverChanged = onHoverChanged
        self.onActiveCornerChanged = onActiveCornerChanged
        self.onResizeChanged = onResizeChanged
        self.onResizeEnded = onResizeEnded
        invalidateCursorRects()
    }

    private func updateHover(with event: NSEvent) {
        let corner = corner(for: event)
        setHoveredCorner(corner)
        if let corner {
            corner.cursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func setHoveredCorner(_ corner: ParagraphHighlightResizeCorner?) {
        guard hoveredCorner != corner else { return }
        hoveredCorner = corner
        onHoverChanged(corner)
    }

    private func corner(for event: NSEvent) -> ParagraphHighlightResizeCorner? {
        corner(at: convert(event.locationInWindow, from: nil))
    }

    private func corner(at point: CGPoint) -> ParagraphHighlightResizeCorner? {
        ParagraphHighlightResizeHitTesting.corner(
            at: point,
            in: bounds.size,
            handleSize: handleSize
        )
    }

    private func invalidateCursorRects() {
        window?.invalidateCursorRects(for: self)
    }
}

final class ParagraphHighlightWindowController: NSWindowController {
    private let model = ParagraphHighlightViewModel()
    private let hostingView: NSHostingView<AnyView>
    private var resizeStartFrame: CGRect?
    private var resizeStartMouseLocation: CGPoint?
    private let minimumResizeSize = CGSize(width: 80, height: 24)

    var onResizeBegan: (() -> Void)?
    var onResizeCompleted: ((CGRect) -> Void)?

    override init(window: NSWindow?) {
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        super.init(window: panel)
        CaptureExclusionRegistry.shared.register(panel)
    }

    convenience init() {
        self.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(at rect: CGRect) {
        guard !rect.isEmpty, !rect.isInfinite,
              [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite) else {
            hide()
            return
        }

        hostingView.rootView = AnyView(ParagraphHighlightView(
            model: model,
            onResizeChanged: { [weak self] corner, mouseLocation in
                self?.updateResize(corner: corner, mouseLocation: mouseLocation)
            },
            onResizeEnded: { [weak self] corner, mouseLocation in
                self?.completeResize(corner: corner, mouseLocation: mouseLocation)
            }
        ))
        model.isActive = true
        guard let window else { return }
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func finishGesture(keepingOverlay: Bool) {
        if !keepingOverlay {
            hide()
        }
    }

    func hide() {
        model.isActive = false
        resizeStartFrame = nil
        resizeStartMouseLocation = nil
        hostingView.rootView = AnyView(EmptyView())
        window?.orderOut(nil)
    }

    var visibleFrame: CGRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    private func updateResize(corner: ParagraphHighlightResizeCorner, mouseLocation: CGPoint) {
        guard let window else { return }
        if resizeStartFrame == nil {
            resizeStartFrame = window.frame
            resizeStartMouseLocation = mouseLocation
            model.isActive = false
            onResizeBegan?()
        }
        guard let resizeStartFrame, let resizeStartMouseLocation else { return }
        corner.cursor.set()
        window.setFrame(
            resizedFrame(
                from: resizeStartFrame,
                corner: corner,
                startMouseLocation: resizeStartMouseLocation,
                currentMouseLocation: mouseLocation
            ),
            display: true
        )
    }

    private func completeResize(corner: ParagraphHighlightResizeCorner, mouseLocation: CGPoint) {
        guard let window else { return }
        let startFrame = resizeStartFrame ?? window.frame
        let startMouseLocation = resizeStartMouseLocation ?? mouseLocation
        let finalFrame = resizedFrame(
            from: startFrame,
            corner: corner,
            startMouseLocation: startMouseLocation,
            currentMouseLocation: mouseLocation
        )
        resizeStartFrame = nil
        resizeStartMouseLocation = nil
        model.isActive = true
        window.setFrame(finalFrame, display: true)
        onResizeCompleted?(finalFrame)
    }

    private func resizedFrame(
        from frame: CGRect,
        corner: ParagraphHighlightResizeCorner,
        startMouseLocation: CGPoint,
        currentMouseLocation: CGPoint
    ) -> CGRect {
        let screenDelta = CGSize(
            width: currentMouseLocation.x - startMouseLocation.x,
            height: currentMouseLocation.y - startMouseLocation.y
        )
        return ParagraphHighlightResizeGeometry.resizedFrame(
            from: frame,
            corner: corner,
            screenDelta: screenDelta,
            minimumSize: minimumResizeSize,
            screenFrame: screenFrame(for: frame)
        )
    }

    private func screenFrame(for frame: CGRect) -> CGRect? {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { NSMouseInRect(midpoint, $0.frame, false) })?.frame
            ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.frame
    }
}

enum WordOverlayPlacement {
    case below
    case above
}

enum WordOverlayLayout {
    static let gap: CGFloat = 12
    static let edgeInset: CGFloat = 50

    static func resolve(
        panelHeight: CGFloat,
        anchor: CGPoint,
        screenFrame: CGRect
    ) -> WordOverlayPlacement {
        let spaceBelow = anchor.y - screenFrame.minY - gap - edgeInset
        let spaceAbove = screenFrame.maxY - anchor.y - gap - edgeInset

        if panelHeight <= spaceBelow {
            return .below
        }

        if panelHeight <= spaceAbove {
            return .above
        }

        return spaceBelow >= spaceAbove ? .below : .above
    }
}

struct ParagraphWordPanelLayout {
    let screenFrame: CGRect
    let paragraphFrame: CGRect
    let anchor: CGPoint

    private let gap: CGFloat = 8
    private let preferredWidth: CGFloat = 380
    private let minimumReadingHeight: CGFloat = 160

    private var bounds: CGRect {
        let inset = min(ParagraphOverlayLayout.edgeInset, screenFrame.width / 4, screenFrame.height / 4)
        return screenFrame.insetBy(dx: inset, dy: inset)
    }

    private var leftSpace: CGFloat { paragraphFrame.minX - bounds.minX - gap }
    private var rightSpace: CGFloat { bounds.maxX - paragraphFrame.maxX - gap }
    private var bottomSpace: CGFloat { paragraphFrame.minY - bounds.minY - gap }
    private var topSpace: CGFloat { bounds.maxY - paragraphFrame.maxY - gap }

    private var edge: CGRectEdge {
        if leftSpace >= preferredWidth, rightSpace >= preferredWidth {
            return anchor.x < paragraphFrame.midX ? .minXEdge : .maxXEdge
        }
        if max(leftSpace, rightSpace) >= preferredWidth
            || (max(bottomSpace, topSpace) < minimumReadingHeight && max(leftSpace, rightSpace) >= 280) {
            return rightSpace >= leftSpace ? .maxXEdge : .minXEdge
        }
        if max(bottomSpace, topSpace) < minimumReadingHeight {
            let clearsWordBelow = bounds.minY + minimumReadingHeight < anchor.y
            let clearsWordAbove = bounds.maxY - minimumReadingHeight > anchor.y
            if clearsWordBelow != clearsWordAbove {
                return clearsWordBelow ? .minYEdge : .maxYEdge
            }
        }
        return bottomSpace >= topSpace ? .minYEdge : .maxYEdge
    }

    var maxPanelSize: CGSize {
        switch edge {
        case .minXEdge:
            return CGSize(width: min(preferredWidth, leftSpace), height: bounds.height)
        case .maxXEdge:
            return CGSize(width: min(preferredWidth, rightSpace), height: bounds.height)
        case .minYEdge, .maxYEdge:
            let space = edge == .minYEdge ? bottomSpace : topSpace
            return CGSize(
                width: min(preferredWidth, bounds.width),
                height: min(bounds.height, max(minimumReadingHeight, space))
            )
        }
    }

    func frame(for measuredSize: CGSize) -> CGRect {
        let limit = maxPanelSize
        let size = CGSize(
            width: min(ceil(measuredSize.width), limit.width),
            height: min(ceil(measuredSize.height), limit.height)
        )
        var x = anchor.x - size.width / 2
        var y = anchor.y + 16 - size.height
        switch edge {
        case .minXEdge: x = paragraphFrame.minX - gap - size.width
        case .maxXEdge: x = paragraphFrame.maxX + gap
        case .minYEdge: y = paragraphFrame.minY - gap - size.height
        case .maxYEdge: y = paragraphFrame.maxY + gap
        }
        let origin = CGPoint(
            x: min(max(x, bounds.minX), bounds.maxX - size.width),
            y: min(max(y, bounds.minY), bounds.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }
}

struct ParagraphOverlayLayout {
    static let edgeInset: CGFloat = 8
    private static let gap: CGFloat = 8
    private static let maximumHeightFraction: CGFloat = 0.72
    private static let minimumAdjacentHeight: CGFloat = 280

    let screenFrame: CGRect
    let anchor: CGPoint
    let sourceRect: CGRect?

    private var insetScreenFrame: CGRect {
        let inset = min(Self.edgeInset, screenFrame.width / 4, screenFrame.height / 4)
        return screenFrame.insetBy(dx: inset, dy: inset)
    }

    private var sourceBottom: CGFloat { sourceRect?.minY ?? anchor.y }
    private var sourceTop: CGFloat { sourceRect?.maxY ?? anchor.y }
    private var spaceBelow: CGFloat { sourceBottom - insetScreenFrame.minY - Self.gap }
    private var spaceAbove: CGFloat { insetScreenFrame.maxY - sourceTop - Self.gap }
    private var screenHeightLimit: CGFloat {
        min(insetScreenFrame.height, floor(screenFrame.height * Self.maximumHeightFraction))
    }
    fileprivate var placesBelow: Bool {
        spaceBelow >= min(Self.minimumAdjacentHeight, screenHeightLimit) || spaceBelow >= spaceAbove
    }

    var maxPanelSize: CGSize {
        let heightLimit = if sourceRect != nil {
            min(screenHeightLimit, max(Self.minimumAdjacentHeight, placesBelow ? spaceBelow : spaceAbove))
        } else {
            screenHeightLimit
        }
        return CGSize(width: insetScreenFrame.width, height: heightLimit)
    }

    func frame(for measuredSize: CGSize, manualTopLeft: CGPoint? = nil) -> CGRect {
        let limit = maxPanelSize
        let size = CGSize(
            width: min(ceil(measuredSize.width), limit.width),
            height: min(ceil(measuredSize.height), limit.height)
        )
        let origin: CGPoint
        if let manualTopLeft {
            origin = CGPoint(x: manualTopLeft.x, y: manualTopLeft.y - size.height)
        } else if let sourceRect, size.height > max(spaceAbove, spaceBelow),
                  max(sourceRect.minX - insetScreenFrame.minX, insetScreenFrame.maxX - sourceRect.maxX) >= size.width + Self.gap {
            let roomOnRight = insetScreenFrame.maxX - sourceRect.maxX
            let x = roomOnRight >= size.width + Self.gap ? sourceRect.maxX + Self.gap : sourceRect.minX - Self.gap - size.width
            origin = CGPoint(x: x, y: sourceRect.maxY - size.height)
        } else {
            origin = CGPoint(
                x: sourceRect?.minX ?? (anchor.x + 12),
                y: placesBelow ? sourceBottom - Self.gap - size.height : sourceTop + Self.gap
            )
        }
        return CGRect(origin: clampedOrigin(origin, size: size), size: size)
    }

    func clampedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        guard !screenFrame.isEmpty else { return origin }
        let bounds = insetScreenFrame
        return CGPoint(
            x: min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
    }
}

struct SentencePopupResizeHandle: NSViewRepresentable {
    var onVerticalResize: () -> Void

    func makeNSView(context: Context) -> Grip {
        let grip = Grip()
        grip.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        grip.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        grip.contentTintColor = .secondaryLabelColor
        return grip
    }

    func updateNSView(_ grip: Grip, context: Context) {
        grip.toolTip = L("Resize translation panel")
        grip.onVerticalResize = onVerticalResize
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Grip, context: Context) -> CGSize? {
        CGSize(width: 18, height: 18)
    }

    final class Grip: NSImageView {
        var onVerticalResize: (() -> Void)?
        private var controller: OverlayWindowController? { window?.windowController as? OverlayWindowController }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            super.resetCursorRects()
            if #available(macOS 15.0, *) {
                addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        }

        override func mouseDown(with event: NSEvent) {
            controller?.beginPopupResize(at: NSEvent.mouseLocation)
        }

        override func mouseDragged(with event: NSEvent) {
            controller?.resizePopup(to: NSEvent.mouseLocation, onVerticalResize: onVerticalResize)
        }

        override func mouseUp(with event: NSEvent) {
            controller?.endPopupResize()
        }
    }
}

struct ParagraphReadingCardEntrance: Equatable {
    nonisolated static let sourceAdjacentOffset: CGFloat = 4
    nonisolated static let animatedDuration: TimeInterval = 0.16

    let initialFrame: CGRect
    let initialOpacity: CGFloat
    let duration: TimeInterval

    nonisolated static func resolve(
        finalFrame: CGRect,
        sourceRect: CGRect?,
        reduceMotion: Bool
    ) -> Self {
        guard !reduceMotion else {
            return Self(initialFrame: finalFrame, initialOpacity: 1, duration: 0)
        }

        var initialFrame = finalFrame
        if let sourceRect, !sourceRect.isNull, !sourceRect.isEmpty {
            if finalFrame.maxY <= sourceRect.minY {
                initialFrame.origin.y += sourceAdjacentOffset
            } else if finalFrame.minY >= sourceRect.maxY {
                initialFrame.origin.y -= sourceAdjacentOffset
            }
        }

        return Self(
            initialFrame: initialFrame,
            initialOpacity: 0,
            duration: animatedDuration
        )
    }
}

private struct ParagraphOverlayMotion {
    var targetFrame: CGRect
    private(set) var frame: CGRect
    private(set) var opacity: CGFloat
    private var startTime: TimeInterval?
    private let duration: TimeInterval
    private let keepsTopEdge: Bool
    private let isEntrance: Bool
    private var progress: CGFloat = 0

    init(
        frame: CGRect,
        opacity: CGFloat,
        targetFrame: CGRect,
        duration: TimeInterval,
        keepsTopEdge: Bool,
        isEntrance: Bool
    ) {
        self.frame = frame
        self.opacity = opacity
        self.targetFrame = targetFrame
        self.duration = duration
        self.keepsTopEdge = keepsTopEdge
        self.isEntrance = isEntrance
    }

    mutating func advance(from previousTimestamp: TimeInterval, to targetTimestamp: TimeInterval) -> Bool {
        let startTime = self.startTime ?? previousTimestamp
        self.startTime = startTime
        let elapsed = CGFloat(min(max((targetTimestamp - startTime) / duration, 0), 1))
        let easedProgress = isEntrance
            ? 1 - pow(1 - elapsed, 3)
            : elapsed * elapsed * (3 - 2 * elapsed)
        if easedProgress >= 1 {
            frame = targetFrame
            opacity = 1
            return true
        }

        let nextProgress = max(progress, easedProgress)
        let step = (nextProgress - progress) / (1 - progress)
        let currentEdge = keepsTopEdge ? frame.maxY : frame.minY
        let targetEdge = keepsTopEdge ? targetFrame.maxY : targetFrame.minY
        let edge = currentEdge + (targetEdge - currentEdge) * step
        frame = CGRect(
            x: frame.minX + (targetFrame.minX - frame.minX) * step,
            y: keepsTopEdge ? edge - targetFrame.height : edge,
            width: targetFrame.width,
            height: targetFrame.height
        )
        opacity += (1 - opacity) * step
        progress = nextProgress
        return false
    }
}

// MARK: - Overlay Window Controller

final class OverlayWindowController: NSWindowController {
    private static let allSpacesCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
    ]

    private let model: AppModel
    private let isParagraphWordPanel: Bool
    private let hostingView: NSHostingView<AnyView>
    private var lastAnchor: CGPoint?
    private var manualOrigin: CGPoint?
    private var dragStartOrigin: CGPoint?
    private var popupResizeStart: (pointer: CGPoint, frame: CGRect, maxHeight: CGFloat)?
    private var activeSpaceRestorationWorkItem: DispatchWorkItem?
    private var paragraphOverlayMaxSize: CGSize?
    private var placedParagraphSourceRect: CGRect?
    private var paragraphMotion: ParagraphOverlayMotion?
    private var paragraphDisplayLink: CADisplayLink?
    private let frameTolerance: CGFloat = 0.5
    private let paragraphRelocationDuration: TimeInterval = 0.18

    var isManualParagraphPositioningActive: Bool {
        dragStartOrigin != nil
    }

    private var isParagraphOverlay: Bool {
        guard !isParagraphWordPanel else { return false }
        switch model.overlayState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return false
        }
    }

    init(model: AppModel, isParagraphWordPanel: Bool = false) {
        self.model = model
        self.isParagraphWordPanel = isParagraphWordPanel
        let initialRootView = AnyView(
            OverlayView(isParagraphWordPanel: isParagraphWordPanel).environmentObject(model)
        )
        hostingView = NSHostingView(rootView: initialRootView)
        let panel = OverlayPanel(
            contentRect: CGRect(x: 0, y: 0, width: 380, height: 200),
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
        panel.collectionBehavior = Self.allSpacesCollectionBehavior
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
        CaptureExclusionRegistry.shared.register(panel)
    }

    /// 设置窗口是否接受鼠标事件
    func setInteractive(_ interactive: Bool, requestsKeyboardFocus: Bool = true) {
        window?.ignoresMouseEvents = !interactive
        if interactive, requestsKeyboardFocus {
            window?.makeKey()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    var visibleFrame: CGRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    /// Reassert the panel's Space membership after Mission Control switches
    /// Spaces. macOS can keep an ordered window marked as visible while it is
    /// no longer frontmost in the newly active Space.
    func reassertForActiveSpace() {
        guard let window else { return }
        guard window.isVisible else { return }
        orderFrontRestoringSpaceMembershipIfNeeded()
    }

    func show(
        at anchor: CGPoint,
        makeKey: Bool = false,
        onOrderedFront: (() -> Void)? = nil
    ) {
        guard let window else { return }
        let parent = isParagraphWordPanel ? model.overlayWindowController.window : nil
        guard !isParagraphWordPanel || parent?.isVisible == true else { return }
        lastAnchor = anchor
        let wasVisible = window.isVisible

        if !wasVisible {
            updateOverlayRootView()
        }

        let layout = isParagraphOverlay ? paragraphLayout(for: anchor) : nil
        let targetFrame = measuredFrame(for: anchor, paragraphLayout: layout)

        var pendingEntrance: ParagraphReadingCardEntrance?
        if !wasVisible {
            stopParagraphMotion()
            placedParagraphSourceRect = layout?.sourceRect
            if let layout {
                let entrance = ParagraphReadingCardEntrance.resolve(
                    finalFrame: targetFrame,
                    sourceRect: layout.sourceRect,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                )
                window.alphaValue = entrance.initialOpacity
                window.setFrame(entrance.initialFrame, display: true)
                if entrance.duration > 0 {
                    pendingEntrance = entrance
                }
            } else {
                window.alphaValue = 1
                window.setFrame(targetFrame, display: true)
            }
        } else {
            updateVisibleFrame(targetFrame, paragraphLayout: layout)
        }

        // Reorder even when AppKit reports the window as visible. During a
        // Space switch that state can refer to the previous Space, which used
        // to make the overlay silently remain there.
        if let parent, window.parent !== parent {
            parent.addChildWindow(window, ordered: .above)
        }
        orderFrontRestoringSpaceMembershipIfNeeded()
        if let pendingEntrance, let layout {
            startParagraphMotion(
                to: targetFrame,
                duration: pendingEntrance.duration,
                keepsTopEdge: layout.placesBelow,
                isEntrance: true
            )
        }
        onOrderedFront?()
        if makeKey {
            window.makeKey()
        }
    }

    func hideWindowOnly() {
        popupResizeStart = nil
        if isParagraphWordPanel {
            if let window { window.parent?.removeChildWindow(window) }
        } else {
            model.dismissParagraphWord()
        }
        stopParagraphMotion()
        placedParagraphSourceRect = nil
        window?.orderOut(nil)
        window?.alphaValue = 1
    }

    func move(to anchor: CGPoint) {
        guard let window else { return }
        lastAnchor = anchor
        manualOrigin = nil
        dragStartOrigin = nil
        stopParagraphMotion()
        window.alphaValue = 1
        guard window.isVisible else { return }

        if isParagraphOverlay {
            let layout = paragraphLayout(for: anchor)
            placedParagraphSourceRect = layout.sourceRect
            applyFrameIfNeeded(paragraphFrame(for: layout))
            return
        }

        placedParagraphSourceRect = nil
        let screenFrame = visibleScreenFrame(for: anchor)
        let origin = anchoredOrigin(for: anchor, size: window.frame.size, in: screenFrame)
        let targetFrame = CGRect(origin: origin, size: window.frame.size)
        applyFrameIfNeeded(targetFrame)
    }

    func beginManualPositioning() {
        guard let window, window.isVisible else { return }
        stopParagraphMotion()
        window.alphaValue = 1
        dragStartOrigin = window.frame.origin
        manualOrigin = window.frame.origin
    }

    func moveBy(translation: CGSize) {
        guard let window, window.isVisible else { return }

        let baseOrigin = dragStartOrigin ?? manualOrigin ?? window.frame.origin
        let proposedOrigin = CGPoint(
            x: baseOrigin.x + translation.width,
            y: baseOrigin.y - translation.height
        )
        let screenPoint = CGPoint(
            x: proposedOrigin.x + window.frame.width / 2,
            y: proposedOrigin.y + window.frame.height / 2
        )
        let layout = ParagraphOverlayLayout(
            screenFrame: visibleScreenFrame(for: screenPoint),
            anchor: screenPoint,
            sourceRect: nil
        )
        let clamped = layout.clampedOrigin(proposedOrigin, size: window.frame.size)

        manualOrigin = clamped
        applyOriginIfNeeded(clamped)
    }

    func endManualPositioning() {
        if let window, window.isVisible {
            manualOrigin = window.frame.origin
        }
        dragStartOrigin = nil
    }

    func beginPopupResize(at pointer: CGPoint) {
        guard isParagraphOverlay, let window, window.isVisible else { return }
        stopParagraphMotion()
        window.alphaValue = 1
        let height = model.settings.sentencePopupSize?.maxHeight ?? paragraphLayout(for: pointer).maxPanelSize.height
        popupResizeStart = (pointer: pointer, frame: window.frame, maxHeight: height)
    }

    func resizePopup(to pointer: CGPoint, onVerticalResize: (() -> Void)? = nil) {
        guard let start = popupResizeStart, isParagraphOverlay else { return }
        let dx = pointer.x - start.pointer.x
        let dy = start.pointer.y - pointer.y
        // Allow a little vertical drift while widening a short, content-sized panel.
        let changesHeight = abs(dy) > min(12, max(4, abs(dx) / 4))
        let size = SentencePopupSize(
            width: (start.frame.width + dx).rounded(),
            maxHeight: changesHeight ? (start.frame.height + dy).rounded() : start.maxHeight
        )
        if changesHeight { onVerticalResize?() }
        guard model.settings.sentencePopupSize != size else { return }
        model.settings.sentencePopupSize = size
        refreshLayoutIfNeeded()
    }

    func endPopupResize() {
        popupResizeStart = nil
        model.refreshParagraphOverlayLayoutImmediately()
    }

    func refreshLayoutIfNeeded(at anchor: CGPoint? = nil) {
        guard let window else { return }
        guard window.isVisible else {
            if let anchor {
                lastAnchor = anchor
            }
            return
        }

        let effectiveAnchor = anchor ?? lastAnchor ?? CGPoint(x: window.frame.midX, y: window.frame.maxY)
        lastAnchor = effectiveAnchor
        let layout = isParagraphOverlay ? paragraphLayout(for: effectiveAnchor) : nil
        let targetFrame = measuredFrame(for: effectiveAnchor, paragraphLayout: layout)
        updateVisibleFrame(targetFrame, paragraphLayout: layout)
        if !window.isOnActiveSpace {
            orderFrontRestoringSpaceMembershipIfNeeded()
        }
    }

    func hide() {
        hideWindowOnly()
        lastAnchor = nil
        manualOrigin = nil
        dragStartOrigin = nil
        paragraphOverlayMaxSize = nil
        hostingView.rootView = AnyView(EmptyView().environmentObject(model))
    }

    private func measuredFrame(for anchor: CGPoint, paragraphLayout: ParagraphOverlayLayout?) -> CGRect {
        if isParagraphWordPanel, let paragraphFrame = model.overlayWindowController.visibleFrame {
            let layout = ParagraphWordPanelLayout(
                screenFrame: visibleScreenFrame(for: anchor),
                paragraphFrame: paragraphFrame,
                anchor: anchor
            )
            updateSizeLimit(layout.maxPanelSize)
            return layout.frame(for: measuredContentSize())
        }
        if let paragraphLayout {
            return paragraphFrame(for: paragraphLayout)
        }

        let size = measuredContentSize()
        let origin = anchoredOrigin(for: anchor, size: size, in: visibleScreenFrame(for: anchor))
        return CGRect(origin: origin, size: size)
    }

    private func orderFrontRestoringSpaceMembershipIfNeeded() {
        guard let window else { return }

        // A pending restoration means the window is temporarily using
        // moveToActiveSpace. Keep the temporary behavior until the next main
        // queue pass so WindowServer can register the new Space association.
        if activeSpaceRestorationWorkItem != nil {
            window.orderFrontRegardless()
            return
        }

        window.collectionBehavior = Self.allSpacesCollectionBehavior
        window.orderFrontRegardless()

        // AppKit can continue reporting the previous Space as active until
        // WindowServer completes the order operation. Validate on the next
        // main queue pass before deciding whether recovery is necessary.
        let validation = DispatchWorkItem { [weak self, weak window] in
            guard let self,
                  let window,
                  self.window === window else {
                return
            }
            self.activeSpaceRestorationWorkItem = nil
            guard window.isVisible, !window.isOnActiveSpace else { return }
            self.moveToActiveSpaceAndScheduleAllSpacesRestoration(for: window)
        }
        activeSpaceRestorationWorkItem = validation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: validation)
    }

    private func moveToActiveSpaceAndScheduleAllSpacesRestoration(for window: NSWindow) {
        // Exiting another app's full-screen Space can strand an ordered window
        // on the old desktop even though collectionBehavior still reports
        // canJoinAllSpaces. Moving to the active Space first makes AppKit
        // rebuild that private association. Restore all-Spaces membership on
        // the next main queue pass, after WindowServer has accepted the move.
        window.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .stationary,
        ]
        window.orderFrontRegardless()

        let restoration = DispatchWorkItem { [weak self, weak window] in
            guard let self,
                  let window,
                  self.window === window else {
                return
            }
            self.activeSpaceRestorationWorkItem = nil
            window.collectionBehavior = Self.allSpacesCollectionBehavior
            if window.isVisible {
                window.orderFrontRegardless()
            }
        }
        activeSpaceRestorationWorkItem = restoration
        DispatchQueue.main.async(execute: restoration)
    }

    private func paragraphLayout(for anchor: CGPoint) -> ParagraphOverlayLayout {
        let sourceRect = manualOrigin == nil ? model.activeParagraphRect : nil
        let sourceCenter = sourceRect.map { CGPoint(x: $0.midX, y: $0.midY) }
        return ParagraphOverlayLayout(
            screenFrame: visibleScreenFrame(for: manualOrigin ?? sourceCenter ?? anchor),
            anchor: anchor,
            sourceRect: sourceRect
        )
    }

    private func paragraphFrame(for layout: ParagraphOverlayLayout) -> CGRect {
        let maxSize = layout.screenFrame.isEmpty ? nil : layout.maxPanelSize
        updateSizeLimit(maxSize)

        let measuredSize = measuredContentSize()
        guard maxSize != nil else { return CGRect(origin: layout.anchor, size: measuredSize) }

        let manualTopLeft = popupResizeStart.map { CGPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? manualOrigin.map {
            CGPoint(x: $0.x, y: $0.y + (window?.frame.height ?? 0))
        }
        let frame = layout.frame(for: measuredSize, manualTopLeft: manualTopLeft)
        if manualOrigin != nil {
            manualOrigin = frame.origin
        }
        return frame
    }

    private func measuredContentSize() -> CGSize {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    private func updateSizeLimit(_ maxSize: CGSize?) {
        guard paragraphOverlayMaxSize != maxSize else { return }
        paragraphOverlayMaxSize = maxSize
        updateOverlayRootView()
    }

    private func updateOverlayRootView() {
        hostingView.rootView = AnyView(
            OverlayView(paragraphOverlayMaxSize: paragraphOverlayMaxSize, isParagraphWordPanel: isParagraphWordPanel)
                .environmentObject(model)
        )
    }

    private func visibleScreenFrame(for anchor: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func updateVisibleFrame(_ targetFrame: CGRect, paragraphLayout: ParagraphOverlayLayout?) {
        guard let window else { return }
        let previousSourceRect = placedParagraphSourceRect
        placedParagraphSourceRect = paragraphLayout?.sourceRect
        if let paragraphLayout, manualOrigin == nil,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if previousSourceRect == paragraphLayout.sourceRect, paragraphMotion != nil {
                paragraphMotion?.targetFrame = targetFrame
                return
            }
            if paragraphLayout.sourceRect != nil, previousSourceRect != paragraphLayout.sourceRect,
               frameNeedsUpdate(from: window.frame, to: targetFrame) {
                startParagraphMotion(
                    to: targetFrame,
                    duration: paragraphRelocationDuration,
                    keepsTopEdge: paragraphLayout.placesBelow,
                    isEntrance: false
                )
                return
            }
        }

        stopParagraphMotion()
        if window.alphaValue != 1 {
            window.alphaValue = 1
        }
        applyFrameIfNeeded(targetFrame)
    }

    private func startParagraphMotion(
        to targetFrame: CGRect,
        duration: TimeInterval,
        keepsTopEdge: Bool,
        isEntrance: Bool
    ) {
        guard let window else { return }
        guard window.screen != nil else {
            stopParagraphMotion()
            window.alphaValue = 1
            applyFrameIfNeeded(targetFrame)
            return
        }

        paragraphMotion = ParagraphOverlayMotion(
            frame: window.frame,
            opacity: window.alphaValue,
            targetFrame: targetFrame,
            duration: duration,
            keepsTopEdge: keepsTopEdge,
            isEntrance: isEntrance
        )
        guard paragraphDisplayLink == nil else { return }
        let displayLink = window.displayLink(target: self, selector: #selector(updateParagraphMotion(_:)))
        paragraphDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func updateParagraphMotion(_ displayLink: CADisplayLink) {
        guard var motion = paragraphMotion, let window else {
            stopParagraphMotion()
            return
        }

        let isComplete = motion.advance(from: displayLink.timestamp, to: displayLink.targetTimestamp)
        paragraphMotion = motion
        applyFrameIfNeeded(motion.frame, display: false)
        if window.alphaValue != motion.opacity {
            window.alphaValue = motion.opacity
        }
        if isComplete {
            stopParagraphMotion()
        }
    }

    private func stopParagraphMotion() {
        paragraphDisplayLink?.invalidate()
        paragraphDisplayLink = nil
        paragraphMotion = nil
    }

    private func applyFrameIfNeeded(_ targetFrame: CGRect, display: Bool = true) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }

        let widthDelta = abs(window.frame.size.width - targetFrame.size.width)
        let heightDelta = abs(window.frame.size.height - targetFrame.size.height)
        if widthDelta <= frameTolerance, heightDelta <= frameTolerance {
            applyOriginIfNeeded(targetFrame.origin)
            return
        }

        let previousFrame = window.frame
        window.setFrame(targetFrame, display: display)
        if display {
            hostingView.layoutSubtreeIfNeeded()
        }
        refreshChildPanel(afterMovingFrom: previousFrame)
    }

    private func applyOriginIfNeeded(_ targetOrigin: CGPoint) {
        guard let window else { return }

        let xNeedsUpdate = abs(window.frame.origin.x - targetOrigin.x) > frameTolerance
        let yNeedsUpdate = abs(window.frame.origin.y - targetOrigin.y) > frameTolerance
        guard xNeedsUpdate || yNeedsUpdate else { return }

        let previousFrame = window.frame
        window.setFrameOrigin(targetOrigin)
        refreshChildPanel(afterMovingFrom: previousFrame)
    }

    private func refreshChildPanel(afterMovingFrom previousFrame: CGRect) {
        guard let window,
              let child = window.childWindows?.lazy.compactMap({ $0.windowController as? OverlayWindowController })
                .first(where: { $0.isParagraphWordPanel }),
              let anchor = child.lastAnchor else { return }
        let updatedAnchor = CGPoint(
            x: anchor.x + window.frame.minX - previousFrame.minX,
            y: anchor.y + window.frame.maxY - previousFrame.maxY
        )
        child.refreshLayoutIfNeeded(at: updatedAnchor)
    }

    private func frameNeedsUpdate(from current: CGRect, to target: CGRect) -> Bool {
        abs(current.origin.x - target.origin.x) > frameTolerance
            || abs(current.origin.y - target.origin.y) > frameTolerance
            || abs(current.size.width - target.size.width) > frameTolerance
            || abs(current.size.height - target.size.height) > frameTolerance
    }

    private func anchoredOrigin(for anchor: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        let placement = WordOverlayLayout.resolve(
            panelHeight: size.height,
            anchor: anchor,
            screenFrame: screenFrame
        )

        let offsetX: CGFloat = 12
        let proposedOrigin: CGPoint

        switch placement {
        case .below:
            proposedOrigin = CGPoint(x: anchor.x + offsetX, y: anchor.y - WordOverlayLayout.gap - size.height)
        case .above:
            proposedOrigin = CGPoint(x: anchor.x + offsetX, y: anchor.y + WordOverlayLayout.gap)
        }

        return clampedOrigin(proposedOrigin, size: size, in: screenFrame)
    }

    private func clampedOrigin(_ proposedOrigin: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        var origin = proposedOrigin
        let shadowMargin: CGFloat = 50
        let minX = screenFrame.minX + shadowMargin
        let maxX = screenFrame.maxX - size.width - shadowMargin
        let minY = screenFrame.minY + shadowMargin
        let maxY = screenFrame.maxY - size.height - shadowMargin
        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)
        return origin
    }
}
