//
//  Snap_TranslateApp.swift
//  Snap Translate
//
//  Created by 杨玉杰 on 2026/1/12.
//

import AppKit
import Combine
import SwiftUI
import Translation

@main
struct Snap_TranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var visibilityTask: Task<Void, Never>?
    private var isManualWindowOpen = false
    private var shouldShowWindowAfterPermissionGrant = false

    private var settingsWindow: NSWindow? {
        settingsWindowController?.window
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        checkPermissionGrantRestart()

        if #available(macOS 15.0, *) {
            createTranslationServiceWindow(model: model)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                warmupServices(model: self.model)
            }
        }

        model.permissions.$status
            .sink { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$continuousTranslation
            .sink { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$sourceLanguage
            .combineLatest(model.settings.$targetLanguage)
            .sink { [weak self] _, _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        Task {
            await refreshAndUpdateVisibility()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        isManualWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showSettingsWindow()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        hideDockIcon()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindow else { return }
        isManualWindowOpen = true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            button.toolTip = "SnapTra Translator"
        }
        statusItem = item
    }

    private func makeStatusBarImage() -> NSImage? {
        if let image = NSImage(named: "StatusBarIcon")?.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        if let sourceImage = NSApp.applicationIconImage,
           let image = sourceImage.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        return nil
    }

    @objc private func statusItemClicked() {
        isManualWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showSettingsWindow()
        }
    }

    private func checkPermissionGrantRestart() {
        let lastStatus = UserDefaults.standard.bool(forKey: AppSettingKey.lastScreenRecordingStatus)
        let currentStatus = CGPreflightScreenCaptureAccess()
        
        if !lastStatus && currentStatus {
            shouldShowWindowAfterPermissionGrant = true
        }
        
        UserDefaults.standard.set(currentStatus, forKey: AppSettingKey.lastScreenRecordingStatus)
    }

    private func refreshAndUpdateVisibility() async {
        await model.permissions.refreshStatusAsync()
        await updateVisibilityFromCurrentState()
    }

    private func scheduleVisibilityUpdate() {
        visibilityTask?.cancel()
        visibilityTask = Task { [weak self] in
            guard let self else { return }
            await self.updateVisibilityFromCurrentState()
        }
    }

    private func updateVisibilityFromCurrentState() async {
        var needsSettings = !model.permissions.status.screenRecording

        if #available(macOS 15.0, *) {
            let status = await model.languagePackManager?.checkLanguagePairQuiet(
                from: model.settings.sourceLanguage,
                to: model.settings.targetLanguage
            )
            if let status {
                needsSettings = needsSettings || status != .installed
            } else {
                needsSettings = true
            }
        }

        if needsSettings {
            showSettingsWindow()
        } else if shouldShowWindowAfterPermissionGrant {
            shouldShowWindowAfterPermissionGrant = false
            isManualWindowOpen = true
            showSettingsWindow()
        } else if !isManualWindowOpen {
            hideDockIcon()
        }
    }

    private func showSettingsWindow() {
        let windowController = settingsWindowController ?? SettingsWindowController(model: model)
        settingsWindowController = windowController
        settingsWindow?.delegate = self
        NSApp.setActivationPolicy(.regular)
        windowController.showWindow(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideDockIcon() {
        isManualWindowOpen = false
        settingsWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let contentView = ContentView()
            .environmentObject(model)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 640)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "SnapTra Translator"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(macOS 15.0, *)
func createTranslationServiceWindow(model: AppModel) {
    guard TranslationServiceWindowHolder.shared.window == nil else { return }

    let translationView = TranslationBridgeView(
        bridge: model.translationBridge,
        settings: model.settings
    )

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

    TranslationServiceWindowHolder.shared.window = window
}

@available(macOS 15.0, *)
class TranslationServiceWindowHolder {
    static let shared = TranslationServiceWindowHolder()
    var window: NSWindow?
    private init() {}
}

@available(macOS 15.0, *)
func warmupServices(model: AppModel) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)

        let sourceLanguage = Locale.Language(identifier: model.settings.sourceLanguage)
        let targetLanguage = Locale.Language(identifier: model.settings.targetLanguage)

        _ = try? await model.translationBridge.translate(
            text: "hello",
            source: sourceLanguage,
            target: targetLanguage,
            timeout: 10.0
        )

        print("✅ Translation service warmed up (source: \(model.settings.sourceLanguage), target: \(model.settings.targetLanguage))")
    }
}
