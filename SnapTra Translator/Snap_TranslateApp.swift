//
//  Snap_TranslateApp.swift
//  Snap Translate
//
//  Created by 杨玉杰 on 2026/1/12.
//

import AppKit
import Combine
import SwiftUI

@main
struct Snap_TranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(#selector(AppDelegate.openSettingsWindow), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    @MainActor private lazy var model = AppModel()
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var visibilityTask: Task<Void, Never>?
    private var isManualWindowOpen = false
    private var shouldShowWindowAfterPermissionGrant = false
    private var hasCompletedInitialLanguageAvailabilityCheck = false

    private var settingsWindow: NSWindow? {
        settingsWindowController?.window
    }

    // Store menu items that need state updates
    private weak var pronunciationMenuItem: NSMenuItem?
    private weak var wordPronunciationMenuItem: NSMenuItem?
    private weak var sentencePronunciationMenuItem: NSMenuItem?
    private weak var continuousTranslationMenuItem: NSMenuItem?
    private weak var providerInfoMenuItem: NSMenuItem?
    #if DEBUG
    private weak var debugShowChannelMenuItem: NSMenuItem?
    #endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        configureStatusItem()
        checkPermissionGrantRestart()

        if #available(macOS 15.0, *),
           let provider = model.primaryTranslation as? MacPrimaryTranslationProvider {
            MacTranslationServiceHost.installIfNeeded(for: provider)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                MacTranslationServiceHost.warmupIfNeeded(
                    provider: provider,
                    sourceLanguage: self.model.settings.sourceLanguage,
                    targetLanguage: self.model.settings.targetLanguage
                )
            }
        }

        model.permissions.statusPublisher
            .sink { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$continuousTranslation
            .sink { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$playWordPronunciation
            .combineLatest(model.settings.$playSentencePronunciation)
            .combineLatest(model.settings.$wordTTSProvider)
            .combineLatest(model.settings.$sentenceTTSProvider)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateDynamicMenuItems()
                }
            }
            .store(in: &cancellables)

        model.settings.$sourceLanguage
            .combineLatest(model.settings.$targetLanguage)
            .sink { [weak self] _, _ in
                self?.scheduleVisibilityUpdate()
            }
            .store(in: &cancellables)

        model.settings.$showMenuBarIcon
            .sink { [weak self] show in
                Task { @MainActor in
                    self?.updateStatusItemVisibility(show: show)
                }
            }
            .store(in: &cancellables)

        // Listen for language changes to update menu
        NotificationCenter.default.publisher(for: .languageChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMenuLanguage()
                }
            }
            .store(in: &cancellables)

        #if DEBUG
        // Listen for debugShowChannelSelector changes to refresh settings window size
        model.settings.$debugShowChannelSelector
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshSettingsWindowSize()
                }
            }
            .store(in: &cancellables)
        #endif

        // Initialize localization manager with saved language
        LocalizationManager.shared.setLanguage(model.settings.appLanguage)

        // Initialize Sparkle auto-updater
        UpdateChecker.shared.initialize()
        UpdateChecker.shared.startAutoCheckIfNeeded()

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

    @MainActor private func configureStatusItem() {
        guard model.settings.showMenuBarIcon else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = "SnapTra Translator"
        }

        let menu = createStatusBarMenu()
        item.menu = menu

        statusItem = item
    }

    @MainActor private func updateStatusItemVisibility(show: Bool) {
        if show {
            if statusItem == nil {
                configureStatusItem()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    @MainActor private func createStatusBarMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        
        // Header section - SnapTra title (styled as header, not disabled item)
        let titleItem = createHeaderMenuItem(title: "SnapTra")
        menu.addItem(titleItem)
        
        menu.addItem(.separator())
        
        // Status section - toggle items with checkmarks
        // Continuous translation toggle
        let continuousItem = NSMenuItem(
            title: L("Continuous Translation"),
            action: #selector(toggleContinuousTranslation),
            keyEquivalent: ""
        )
        continuousItem.target = self
        menu.addItem(continuousItem)
        self.continuousTranslationMenuItem = continuousItem

        // Pronunciation submenu
        let pronunciationSubmenu = NSMenu()
        
        let wordPronunciationItem = NSMenuItem(
            title: L("Word"),
            action: #selector(toggleWordPronunciation),
            keyEquivalent: ""
        )
        wordPronunciationItem.target = self
        pronunciationSubmenu.addItem(wordPronunciationItem)
        self.wordPronunciationMenuItem = wordPronunciationItem
        
        let sentencePronunciationItem = NSMenuItem(
            title: L("Sentence"),
            action: #selector(toggleSentencePronunciation),
            keyEquivalent: ""
        )
        sentencePronunciationItem.target = self
        pronunciationSubmenu.addItem(sentencePronunciationItem)
        self.sentencePronunciationMenuItem = sentencePronunciationItem
        
        // Provider info in submenu
        let providerItem = NSMenuItem(
            title: "",
            action: nil,
            keyEquivalent: ""
        )
        providerItem.isEnabled = false
        providerItem.indentationLevel = 1
        pronunciationSubmenu.addItem(providerItem)
        self.providerInfoMenuItem = providerItem
        
        let pronunciationMenuItem = NSMenuItem(
            title: L("Pronunciation"),
            action: nil,
            keyEquivalent: ""
        )
        pronunciationMenuItem.submenu = pronunciationSubmenu
        menu.addItem(pronunciationMenuItem)
        self.pronunciationMenuItem = pronunciationMenuItem
        
        // Actions section
        // Settings
        let settingsItem = NSMenuItem(
            title: L("Settings..."),
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // About
        let aboutItem = NSMenuItem(
            title: L("About SnapTra"),
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        #if DEBUG
        // Debug section
        menu.addItem(.separator())

        // Debug: Show Update Channel Selector
        let debugShowChannelItem = NSMenuItem(
            title: "GitHub Release",
            action: #selector(toggleDebugShowChannelSelector),
            keyEquivalent: ""
        )
        debugShowChannelItem.target = self
        menu.addItem(debugShowChannelItem)
        self.debugShowChannelMenuItem = debugShowChannelItem
        #endif

        // Quit
        let quitItem = NSMenuItem(
            title: L("Quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Update dynamic menu item states
        updateDynamicMenuItems()
        
        return menu
    }
    
    /// Creates a header-style menu item that looks like a title rather than a disabled item
    private func createHeaderMenuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        
        // Use attributed string for better visual hierarchy
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        
        return item
    }

    @MainActor private func updateDynamicMenuItems() {
        // Update pronunciation submenu item states
        wordPronunciationMenuItem?.state = model.settings.playWordPronunciation ? .on : .off
        sentencePronunciationMenuItem?.state = model.settings.playSentencePronunciation ? .on : .off
        
        // Update continuous translation menu item state (checkmark)
        continuousTranslationMenuItem?.state = model.settings.continuousTranslation ? .on : .off
        
        // Update provider info item to show both Word and Sentence providers
        let wordProvider = model.settings.wordTTSProvider
        let sentenceProvider = model.settings.sentenceTTSProvider
        let wordName = wordProvider == .apple ? L("System") : wordProvider.displayName
        let sentenceName = sentenceProvider == .apple ? L("System") : sentenceProvider.displayName
        let providerTitle = "\(L("Word")): \(wordName)  ·  \(L("Sentence")): \(sentenceName)"
        
        // Style the provider info with secondary color
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        providerInfoMenuItem?.attributedTitle = NSAttributedString(
            string: providerTitle,
            attributes: attributes
        )
        
        #if DEBUG
        // Update debug menu item state
        debugShowChannelMenuItem?.state = model.settings.debugShowChannelSelector ? .on : .off
        #endif
    }

    @MainActor private func updateMenuLanguage() {
        // Recreate menu with new language
        if let item = statusItem {
            let menu = createStatusBarMenu()
            item.menu = menu
        }
    }

    // MARK: - NSMenuDelegate

    @MainActor func menuWillOpen(_ menu: NSMenu) {
        // Update menu item states before showing
        updateDynamicMenuItems()
    }

    // This method is kept for compatibility but no longer used
    // When statusItem.menu is set, the system handles menu display automatically
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {}

    @MainActor @objc private func toggleWordPronunciation() {
        model.settings.playWordPronunciation.toggle()
    }

    @MainActor @objc private func toggleSentencePronunciation() {
        model.settings.playSentencePronunciation.toggle()
    }

    @MainActor @objc private func toggleContinuousTranslation() {
        model.settings.continuousTranslation.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @MainActor @objc private func openAbout() {
        openSettings(initialTab: .about)
    }

    @MainActor @objc func openSettingsWindow() {
        openSettings(initialTab: .general)
    }

    @MainActor
    private func openSettings(initialTab: SettingsTab) {
        isManualWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        if let window = settingsWindow, window.isVisible {
            NotificationCenter.default.post(name: .switchSettingsTab, object: initialTab)
            // Defer activation to after the status bar menu fully closes,
            // otherwise makeKeyAndOrderFront may fail while the menu is dismissing.
            DispatchQueue.main.async {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            showSettingsWindow(initialTab: initialTab)
        }
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
            await self?.updateVisibilityFromCurrentState()
        }
    }

    @MainActor
    private func updateVisibilityFromCurrentState() async {
        var needsSettings = !model.permissions.status.screenRecording

        if #available(macOS 15.0, *) {
            let status = await model.refreshLanguageAvailabilityStatusForCurrentSettings(
                retrySupportedStatus: !hasCompletedInitialLanguageAvailabilityCheck
            )
            hasCompletedInitialLanguageAvailabilityCheck = true
            needsSettings = needsSettings || status != .installed
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

    @MainActor
    private func showSettingsWindow(initialTab: SettingsTab = .general) {
        let windowController = settingsWindowController ?? SettingsWindowController(model: model, initialTab: initialTab)
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

    #if DEBUG
    @objc private func toggleDebugShowChannelSelector() {
        model.settings.debugShowChannelSelector.toggle()
        updateDynamicMenuItems()
    }

    @MainActor
    private func refreshSettingsWindowSize() {
        guard let window = settingsWindow, window.isVisible else { return }
        
        if window.contentView is NSHostingView<SettingsWindowView> {
            settingsWindowController?.close()
            settingsWindowController = nil
            showSettingsWindow(initialTab: .about)
        }
    }
    #endif

}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel, initialTab: SettingsTab = .general) {
        let contentView = SettingsWindowView(initialTab: initialTab)
            .environmentObject(model)
        let hostingView = NSHostingView(rootView: contentView)
        let initialContentSize = SettingsWindowLayout.windowContentSize(for: initialTab)
        let initialContentRect = NSRect(origin: .zero, size: initialContentSize)
        hostingView.frame = initialContentRect

        let window = NSWindow(
            contentRect: initialContentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = L("Settings")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
