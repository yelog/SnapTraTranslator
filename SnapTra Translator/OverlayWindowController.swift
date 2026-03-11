import AppKit
import SwiftUI

private final class OverlayPanel: NSPanel {
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
    private var hostingView: NSHostingView<DebugOCRBorderView>

    override init(window: NSWindow?) {
        hostingView = NSHostingView(rootView: DebugOCRBorderView(wordBoxes: []))
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
        hostingView.rootView = DebugOCRBorderView(wordBoxes: wordBoxes)
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Paragraph Highlight View

private struct ParagraphHighlightView: View {
    private let accentColor = Color(red: 0.18, green: 0.88, blue: 0.42)
    private let lineWidth: CGFloat = 2.5
    /// Half-width of the soft gradient halo on each side of the beam core
    private let beamHaloHalf: CGFloat = 28
    /// Width of the hard bright core line
    private let beamCoreWidth: CGFloat = 2.5
    /// Single-pass duration in seconds (left→right or right→left)
    private let scanDuration: TimeInterval = 1.4

    @State private var appeared = false
    @State private var startDate: Date = .now

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let cornerLength = min(min(size.width, size.height) * 0.22, 22)

            ZStack {
                // Layer 1 — ambient fill
                Rectangle()
                    .fill(accentColor.opacity(0.05))

                // Layer 2 — scan beam via TimelineView so Canvas re-renders every frame
                TimelineView(.animation) { timeline in
                    Canvas { ctx, canvasSize in
                        let elapsed = timeline.date.timeIntervalSince(startDate)
                        let centerX = beamCenterX(elapsed: elapsed, width: canvasSize.width)
                        drawBeam(ctx: ctx, canvasSize: canvasSize, centerX: centerX)
                    }
                }

                // Layer 3 — corner brackets
                cornerBrackets(size: size, cornerLength: cornerLength)
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
            .onAppear {
                startDate = .now
                withAnimation(.easeOut(duration: 0.25)) {
                    appeared = true
                }
            }
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

    private func cornerBrackets(size: CGSize, cornerLength: CGFloat) -> Path {
        Path { path in
            let rect = CGRect(origin: .zero, size: size)

            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))

            path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))

            path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

            path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        }
    }
}

final class ParagraphHighlightWindowController: NSWindowController {
    private let hostingView: NSHostingView<ParagraphHighlightView>

    override init(window: NSWindow?) {
        hostingView = NSHostingView(rootView: ParagraphHighlightView())
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
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
    }

    convenience init() {
        self.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(at rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else {
            hide()
            return
        }

        guard let window else { return }
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

// MARK: - Overlay Window Controller

final class OverlayWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>
    private var lastAnchor: CGPoint?
    private var manualOrigin: CGPoint?
    private var dragStartOrigin: CGPoint?
    private let frameTolerance: CGFloat = 0.5

    init(model: AppModel) {
        hostingView = NSHostingView(rootView: AnyView(OverlayView().environmentObject(model)))
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
    }

    /// 设置窗口是否接受鼠标事件
    func setInteractive(_ interactive: Bool) {
        window?.ignoresMouseEvents = !interactive
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(at anchor: CGPoint, makeKey: Bool = false) {
        guard let window else { return }
        lastAnchor = anchor
        let targetFrame = measuredFrame(for: anchor)

        if !window.isVisible {
            window.setFrame(targetFrame, display: true)
            window.orderFrontRegardless()
            if makeKey {
                window.makeKey()
            }
        } else {
            applyFrameIfNeeded(targetFrame)
        }
    }

    func move(to anchor: CGPoint) {
        guard let window else { return }
        lastAnchor = anchor
        manualOrigin = nil
        dragStartOrigin = nil
        guard window.isVisible else { return }

        let screenFrame = visibleScreenFrame(for: anchor)
        let origin = anchoredOrigin(for: anchor, size: window.frame.size, in: screenFrame)
        let targetFrame = CGRect(origin: origin, size: window.frame.size)
        applyFrameIfNeeded(targetFrame)
    }

    /// 将面板对齐到句子矩形（正上方或正下方，取决于哪侧空间更大）
    func alignToSentenceRect(_ sentenceRect: CGRect, animated: Bool = true) {
        guard let window else { return }

        // 强制 SwiftUI 重新布局以获得最新宽高
        hostingView.layoutSubtreeIfNeeded()
        let contentSize = hostingView.fittingSize

        let panelWidth  = contentSize.width
        let panelHeight = contentSize.height

        // 取句子中心点所在屏幕
        let midPoint = CGPoint(x: sentenceRect.midX, y: sentenceRect.midY)
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(midPoint, $0.frame, false)
        }) ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero

        // AppKit Y 轴向上：minY 是物理下边，maxY 是物理上边
        let gap: CGFloat = 8
        let spaceBelow = sentenceRect.minY - screenFrame.minY
        let spaceAbove = screenFrame.maxY - sentenceRect.maxY

        let panelY: CGFloat
        if spaceBelow >= panelHeight + gap {
            // 句子正下方（面板顶边贴近句子底边）
            panelY = sentenceRect.minY - panelHeight - gap
        } else {
            // 句子正上方（面板底边贴近句子顶边）
            panelY = sentenceRect.maxY + gap
        }

        // 水平左对齐句子，clamp 到屏幕范围内
        let margin: CGFloat = 8
        var panelX = sentenceRect.minX
        panelX = max(screenFrame.minX + margin, panelX)
        panelX = min(screenFrame.maxX - panelWidth - margin, panelX)

        let targetFrame = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        if animated {
            applyFrameAnimated(targetFrame)
        } else {
            applyFrameIfNeeded(targetFrame)
        }
    }

    func beginManualPositioning() {
        guard let window, window.isVisible else { return }
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
        let screenFrame = visibleScreenFrame(for: screenPoint)
        let clamped = clampedOrigin(proposedOrigin, size: window.frame.size, in: screenFrame)

        manualOrigin = clamped
        applyOriginIfNeeded(clamped)
    }

    func endManualPositioning() {
        dragStartOrigin = nil
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
        let targetFrame = measuredFrame(for: effectiveAnchor)
        applyFrameIfNeeded(targetFrame)
    }

    func hide() {
        lastAnchor = nil
        manualOrigin = nil
        dragStartOrigin = nil
        window?.orderOut(nil)
    }

    private func measuredFrame(for anchor: CGPoint) -> CGRect {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let origin: CGPoint

        if let manualOrigin {
            let screenPoint = CGPoint(
                x: manualOrigin.x + size.width / 2,
                y: manualOrigin.y + size.height / 2
            )
            let screenFrame = visibleScreenFrame(for: screenPoint)
            origin = clampedOrigin(manualOrigin, size: size, in: screenFrame)
            self.manualOrigin = origin
        } else {
            let screenFrame = visibleScreenFrame(for: anchor)
            origin = anchoredOrigin(for: anchor, size: size, in: screenFrame)
        }

        return CGRect(origin: origin, size: size)
    }

    private func visibleScreenFrame(for anchor: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func applyFrameAnimated(_ targetFrame: CGRect) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func applyFrameIfNeeded(_ targetFrame: CGRect) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }

        let widthDelta = abs(window.frame.size.width - targetFrame.size.width)
        let heightDelta = abs(window.frame.size.height - targetFrame.size.height)
        if widthDelta <= frameTolerance, heightDelta <= frameTolerance {
            applyOriginIfNeeded(targetFrame.origin)
            return
        }

        window.setFrame(targetFrame, display: true)
    }

    private func applyOriginIfNeeded(_ targetOrigin: CGPoint) {
        guard let window else { return }

        let xNeedsUpdate = abs(window.frame.origin.x - targetOrigin.x) > frameTolerance
        let yNeedsUpdate = abs(window.frame.origin.y - targetOrigin.y) > frameTolerance
        guard xNeedsUpdate || yNeedsUpdate else { return }

        window.setFrameOrigin(targetOrigin)
    }

    private func frameNeedsUpdate(from current: CGRect, to target: CGRect) -> Bool {
        abs(current.origin.x - target.origin.x) > frameTolerance
            || abs(current.origin.y - target.origin.y) > frameTolerance
            || abs(current.size.width - target.size.width) > frameTolerance
            || abs(current.size.height - target.size.height) > frameTolerance
    }

    private func anchoredOrigin(for anchor: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        let offset = CGPoint(x: 12, y: -12)
        let proposedOrigin = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y - size.height)
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
