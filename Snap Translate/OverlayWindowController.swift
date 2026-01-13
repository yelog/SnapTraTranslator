import AppKit
import SwiftUI

final class OverlayWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>

    init(model: AppModel) {
        hostingView = NSHostingView(rootView: AnyView(OverlayView().environmentObject(model)))
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(at anchor: CGPoint) {
        guard let window else { return }
        let size = hostingView.fittingSize
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        let screenFrame = screen?.frame ?? .zero
        let origin = clampedOrigin(for: anchor, size: size, in: screenFrame)
        window.setFrame(CGRect(origin: origin, size: size), display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func clampedOrigin(for anchor: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        let offset = CGPoint(x: 12, y: -12)
        var origin = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y - size.height)
        let minX = screenFrame.minX + 12
        let maxX = screenFrame.maxX - size.width - 12
        let minY = screenFrame.minY + 12
        let maxY = screenFrame.maxY - size.height - 12
        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)
        return origin
    }
}
