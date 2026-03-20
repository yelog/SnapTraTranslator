import AppKit
import Foundation
import SwiftUI

@available(macOS 15.0, *)
enum MacTranslationServiceHost {
    private static var hasWarmedUp = false

    static func installIfNeeded(for provider: MacPrimaryTranslationProvider) {
        guard MacTranslationServiceWindowHolder.shared.window == nil else { return }

        let translationView = TranslationBridgeView(bridge: provider.bridge)
        let hostingView = NSHostingView(rootView: translationView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setIsVisible(false)

        MacTranslationServiceWindowHolder.shared.window = window
    }

    static func warmupIfNeeded(
        provider: MacPrimaryTranslationProvider,
        sourceLanguage: String,
        targetLanguage: String
    ) {
        guard !hasWarmedUp else { return }
        hasWarmedUp = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)

            _ = try? await provider.translate(
                text: "hello",
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                timeout: 10.0
            )

            print("✅ Translation service warmed up (source: \(sourceLanguage), target: \(targetLanguage))")
        }
    }
}

@available(macOS 15.0, *)
private final class MacTranslationServiceWindowHolder {
    static let shared = MacTranslationServiceWindowHolder()
    var window: NSWindow?

    private init() {}
}
