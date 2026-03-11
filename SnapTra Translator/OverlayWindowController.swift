import AppKit
import SwiftUI

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

// MARK: - Overlay Window Controller

final class OverlayWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>
    private var lastAnchor: CGPoint?
    private let frameTolerance: CGFloat = 0.5

    init(model: AppModel) {
        hostingView = NSHostingView(rootView: AnyView(OverlayView().environmentObject(model)))
        let panel = NSPanel(
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

    func show(at anchor: CGPoint) {
        guard let window else { return }
        lastAnchor = anchor
        let targetFrame = measuredFrame(for: anchor)

        if !window.isVisible {
            window.setFrame(targetFrame, display: true)
            window.orderFrontRegardless()
        } else {
            applyFrameIfNeeded(targetFrame)
        }
    }

    func move(to anchor: CGPoint) {
        guard let window else { return }
        lastAnchor = anchor
        guard window.isVisible else { return }

        let screenFrame = visibleScreenFrame(for: anchor)
        let origin = clampedOrigin(for: anchor, size: window.frame.size, in: screenFrame)
        let targetFrame = CGRect(origin: origin, size: window.frame.size)
        applyFrameIfNeeded(targetFrame)
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
        window?.orderOut(nil)
    }

    private func measuredFrame(for anchor: CGPoint) -> CGRect {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let screenFrame = visibleScreenFrame(for: anchor)
        let origin = clampedOrigin(for: anchor, size: size, in: screenFrame)
        return CGRect(origin: origin, size: size)
    }

    private func visibleScreenFrame(for anchor: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func applyFrameIfNeeded(_ targetFrame: CGRect) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }
        window.setFrame(targetFrame, display: true)
    }

    private func frameNeedsUpdate(from current: CGRect, to target: CGRect) -> Bool {
        abs(current.origin.x - target.origin.x) > frameTolerance
            || abs(current.origin.y - target.origin.y) > frameTolerance
            || abs(current.size.width - target.size.width) > frameTolerance
            || abs(current.size.height - target.size.height) > frameTolerance
    }

    private func clampedOrigin(for anchor: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        let offset = CGPoint(x: 12, y: -12)
        var origin = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y - size.height)
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
