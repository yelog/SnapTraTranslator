//
//  SettingsWindowView.swift
//  SnapTra Translator
//
//  Settings window with tabbed interface (General, Dictionary, About).
//

import AppKit
import SwiftUI
import Translation

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case service = "Service"
    case system = "System"
    case about = "About"
}

extension Notification.Name {
    static let switchSettingsTab = Notification.Name("switchSettingsTab")
}

enum SettingsWindowLayout {
    static let defaultContentWidth: CGFloat = 400
    static let aboutContentWidth: CGFloat = 370
    static let dictionaryContentWidth: CGFloat = 650
    static let generalContentHeight: CGFloat = 650
    static let dictionaryContentHeight: CGFloat = 550
    static let systemContentHeight: CGFloat = 360
    static let aboutContentHeight: CGFloat = 520
    static let aboutContentHeightWithChannelSelector: CGFloat = 650
    static let outerPadding: CGFloat = 16
    static let animationDuration: TimeInterval = 0.24

    static func contentWidth(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .service:
            return dictionaryContentWidth
        case .about:
            return aboutContentWidth
        default:
            return defaultContentWidth
        }
    }

    static func contentHeight(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .general:
            return generalContentHeight
        case .service:
            return dictionaryContentHeight
        case .system:
            return systemContentHeight
        case .about:
            if UpdateChecker.shared.isGitHubRelease {
                return aboutContentHeightWithChannelSelector
            }
            #if DEBUG
            if SettingsStore.shared.debugShowChannelSelector {
                return aboutContentHeightWithChannelSelector
            }
            #endif
            return aboutContentHeight
        }
    }

    static func windowContentSize(for tab: SettingsTab) -> CGSize {
        CGSize(
            width: contentWidth(for: tab) + (outerPadding * 2),
            height: contentHeight(for: tab) + (outerPadding * 2)
        )
    }
}

struct SettingsWindowView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab: SettingsTab
    @State private var languageRefreshToken = UUID()
    @State private var hidesTabScrollIndicator = false
    @State private var scrollIndicatorResetWorkItem: DispatchWorkItem?
    @State private var window: NSWindow?
    var initialTab: SettingsTab = .general

    init(initialTab: SettingsTab = .general) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    /// Dynamic content width based on selected tab
    private var currentContentWidth: CGFloat {
        SettingsWindowLayout.contentWidth(for: selectedTab)
    }

    /// Dynamic content height based on selected tab and debug settings
    private var currentContentHeight: CGFloat {
        switch selectedTab {
        case .general:
            return SettingsWindowLayout.generalContentHeight
        case .service:
            return SettingsWindowLayout.dictionaryContentHeight
        case .system:
            return SettingsWindowLayout.systemContentHeight
        case .about:
            #if DEBUG
            if UpdateChecker.shared.isGitHubRelease || model.settings.debugShowChannelSelector {
                return SettingsWindowLayout.aboutContentHeightWithChannelSelector
            }
            #else
            if UpdateChecker.shared.isGitHubRelease {
                return SettingsWindowLayout.aboutContentHeightWithChannelSelector
            }
            #endif
            return SettingsWindowLayout.aboutContentHeight
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
                .tabItem {
                    Label(L("General"), systemImage: "gear")
                }
                .tag(SettingsTab.general)

            DictionarySettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
                .tabItem {
                    Label(L("Service"), systemImage: "square.grid.2x2")
                }
                .tag(SettingsTab.service)

            SystemSettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
                .tabItem {
                    Label(L("System"), systemImage: "gearshape.2")
                }
                .tag(SettingsTab.system)

            AboutSettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
                .tabItem {
                    Label(L("About"), systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .background(
            SettingsWindowAccessor(window: $window)
        )
        .onReceive(NotificationCenter.default.publisher(for: .switchSettingsTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            // Force refresh when language changes
            languageRefreshToken = UUID()
        }
        .onAppear {
            updateTabScrollIndicator(for: selectedTab, animated: false)
            resizeWindow(for: selectedTab, animated: false)
        }
        .onChange(of: selectedTab) { _, newValue in
            updateTabScrollIndicator(for: newValue, animated: true)
            resizeWindow(for: newValue, animated: true)
        }
        #if DEBUG
        .onChange(of: model.settings.debugShowChannelSelector) { _, _ in
            // When debugShowChannelSelector changes, resize window if on About tab
            if selectedTab == .about {
                resizeWindowWithCurrentHeight(animated: true)
            }
        }
        #endif
        .onDisappear {
            scrollIndicatorResetWorkItem?.cancel()
        }
        .id(languageRefreshToken)
        .frame(
            width: currentContentWidth,
            height: currentContentHeight
        )
        .padding(SettingsWindowLayout.outerPadding)
    }

    private func resizeWindow(for tab: SettingsTab, animated: Bool) {
        guard let window else { return }

        let targetContentSize = SettingsWindowLayout.windowContentSize(for: tab)
        var targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        )
        let currentFrame = window.frame

        // Center horizontally when width changes
        targetFrame.origin.x = currentFrame.midX - targetFrame.width / 2
        // Anchor to top edge
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SettingsWindowLayout.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func resizeWindowWithCurrentHeight(animated: Bool) {
        guard let window else { return }

        // Calculate target size using current dynamic height
        let targetContentSize = CGSize(
            width: currentContentWidth + (SettingsWindowLayout.outerPadding * 2),
            height: currentContentHeight + (SettingsWindowLayout.outerPadding * 2)
        )
        var targetFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        )
        let currentFrame = window.frame

        // Center horizontally when width changes
        targetFrame.origin.x = currentFrame.midX - targetFrame.width / 2
        // Anchor to top edge
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SettingsWindowLayout.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    private func updateTabScrollIndicator(for tab: SettingsTab, animated: Bool) {
        scrollIndicatorResetWorkItem?.cancel()
        scrollIndicatorResetWorkItem = nil

        guard animated else {
            hidesTabScrollIndicator = false
            return
        }

        hidesTabScrollIndicator = true

        let workItem = DispatchWorkItem {
            hidesTabScrollIndicator = false
            scrollIndicatorResetWorkItem = nil
        }
        scrollIndicatorResetWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + SettingsWindowLayout.animationDuration,
            execute: workItem
        )
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            window = nsView.window
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var appeared = false
    var hidesScrollIndicator: Bool = false

    private var supportsSelectedTextTranslation: Bool {
        DistributionChannel.supportsSelectedTextTranslation
    }

    private var hasAnyTranslationCapability: Bool {
        model.permissions.status.screenRecording
            || (
                supportsSelectedTextTranslation
                    && (
                model.settings.selectedTextTranslationEnabled
                    && model.permissions.status.accessibility
                    )
            )
    }

    @available(macOS 15.0, *)
    private var targetLanguageReady: Bool {
        requiredLanguagePairs.allSatisfy { pair in
            if pair.isSameLanguage {
                return true
            }
            return model.languagePackManager?.getStatus(
                from: pair.sourceIdentifier,
                to: pair.targetIdentifier
            ) == .installed
        }
    }

    @available(macOS 15.0, *)
    private var requiredLanguagePairs: [LookupLanguagePair] {
        model.requiredLanguagePairsForCurrentSettings()
    }

    @available(macOS 15.0, *)
    private func refreshLanguageStatuses() async {
        guard let manager = model.languagePackManager else { return }
        for pair in requiredLanguagePairs where !pair.isSameLanguage {
            _ = await manager.checkLanguagePair(from: pair.sourceIdentifier, to: pair.targetIdentifier)
        }
    }

    private var allReady: Bool {
        if #available(macOS 15.0, *) {
            return hasAnyTranslationCapability && targetLanguageReady
        }
        return hasAnyTranslationCapability
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Permissions Section
                VStack(spacing: 0) {
                    GeneralPermissionRow(
                        icon: "rectangle.dashed.badge.record",
                        title: L("Screen Recording"),
                        isGranted: model.permissions.status.screenRecording,
                        action: { model.permissions.requestAndOpenScreenRecording() }
                    )

                    if supportsSelectedTextTranslation {
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)

                        GeneralPermissionRow(
                            icon: "figure.wave",
                            title: L("Accessibility"),
                            isGranted: model.permissions.status.accessibility,
                            action: { model.permissions.requestAndOpenAccessibility() }
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )

                // Settings Section
                VStack(spacing: 0) {
                    HotkeyKeycapSelector(selectedKey: $model.settings.singleKey)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    if #available(macOS 15.0, *) {
                        GeneralTranslationLanguageRow(
                            targetLanguage: $model.settings.targetLanguage,
                            sourceLanguage: $model.settings.sourceLanguage
                        )

                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)

                        ToggleRow(
                            title: L("Bidirectional Translation"),
                            subtitle: L("Automatically reverse direction when text matches the target language"),
                            isOn: $model.settings.bidirectionalTranslationEnabled
                        )
                        .onChange(of: model.settings.bidirectionalTranslationEnabled) { _, _ in
                            Task { @MainActor in
                                await refreshLanguageStatuses()
                            }
                        }

                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Pronunciation"))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.primary)
                            Text(L("Audio playback after translation"))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Text(L("Word"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(model.settings.playWordPronunciation ? Color.accentColor : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(model.settings.playWordPronunciation ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(model.settings.playWordPronunciation ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .onTapGesture {
                                    model.settings.playWordPronunciation.toggle()
                                }

                            Text(L("Sentence"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(model.settings.playSentencePronunciation ? Color.accentColor : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(model.settings.playSentencePronunciation ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(model.settings.playSentencePronunciation ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .onTapGesture {
                                    model.settings.playSentencePronunciation.toggle()
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Copy to Clipboard"))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.primary)
                            Text(L("Auto-copy original text after translation"))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Text(L("Word"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(model.settings.copyWord ? Color.accentColor : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(model.settings.copyWord ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(model.settings.copyWord ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .onTapGesture {
                                    model.settings.copyWord.toggle()
                                }

                            Text(L("Sentence"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(model.settings.copySentence ? Color.accentColor : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(model.settings.copySentence ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(model.settings.copySentence ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                                .onTapGesture {
                                    model.settings.copySentence.toggle()
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: L("Continuous Translation"),
                        subtitle: L("Keep translating as mouse moves"),
                        isOn: $model.settings.continuousTranslation
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: L("Double-tap OCR Sentence Translation"),
                        isOn: $model.settings.ocrSentenceTranslationEnabled
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: L("Hide Original Text"),
                        subtitle: L("Only show translated text in sentence overlays"),
                        isOn: $model.settings.hideOriginalTextInSentenceOverlay
                    )

                    if supportsSelectedTextTranslation {
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)

                        ToggleRow(
                            title: L("Translate Selected Text"),
                            isOn: $model.settings.selectedTextTranslationEnabled
                        )
                    }

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: L("Debug OCR Region"),
                        subtitle: L("Show capture area when shortcut is pressed"),
                        isOn: $model.settings.debugShowOcrRegion
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )

                // Status
                HStack(spacing: 12) {
                    if allReady {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.green)
                            Text(L("Ready to translate"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    Spacer()

                    Button {
                        Task { @MainActor in
                            await model.permissions.refreshStatusAsync()
                            if #available(macOS 15.0, *) {
                                await refreshLanguageStatuses()
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text(L("Refresh"))
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule()
                            .fill(.quaternary)
                    )
                    .contentShape(Capsule())
                }
            }
            .padding()
            .background(
                ScrollViewScrollerConfigurator(
                    hidesVerticalScroller: hidesScrollIndicator
                )
            )
        }
        .scrollIndicators(hidesScrollIndicator ? .hidden : .automatic, axes: .vertical)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task { @MainActor in
                await model.permissions.refreshStatusAsync()
                if #available(macOS 15.0, *) {
                    await refreshLanguageStatuses()
                }
            }
        }
    }
}

// MARK: - Helper Views

struct GeneralPermissionRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isGranted ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                        .shadow(color: isGranted ? .green.opacity(0.5) : .orange.opacity(0.5), radius: 3)

                    Text(isGranted ? L("Granted") : L("Required"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isGranted ? .green : .orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isGranted ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isGranted)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

@available(macOS 15.0, *)
struct GeneralTranslationLanguageRow: View {
    @Binding var targetLanguage: String
    @Binding var sourceLanguage: String
    @EnvironmentObject var model: AppModel
    @State private var showingUnavailableAlert = false
    @State private var unavailableAlertTitle = ""
    @State private var missingLanguagesMessage = ""
    @State private var unavailablePair: LookupLanguagePair?
    @State private var activeLanguageStatusRefreshCount = 0

    private let commonLanguages: [(id: String, name: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("ru", "Русский"),
        ("ar", "العربية"),
        ("th", "ไทย"),
        ("vi", "Tiếng Việt"),
    ]

    private enum LanguageRole {
        case source
        case target
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(L("Translate from"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                languageStatusIcon(for: .source)

                Picker("", selection: $sourceLanguage) {
                    ForEach(commonLanguages, id: \.id) { lang in
                        Text(verbatim: languageMenuLabel(for: .source, language: lang)).tag(lang.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.accentColor)
            }

            HStack(spacing: 12) {
                Text(L("Translate to"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                languageStatusIcon(for: .target)

                Picker("", selection: $targetLanguage) {
                    ForEach(commonLanguages, id: \.id) { lang in
                        Text(verbatim: languageMenuLabel(for: .target, language: lang)).tag(lang.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: sourceLanguage) { _, _ in
            Task { @MainActor in
                await refreshRequiredLanguageStatuses(showLoading: true)
            }
        }
        .onChange(of: targetLanguage) { _, _ in
            Task { @MainActor in
                await refreshRequiredLanguageStatuses(showLoading: true)
            }
        }
        .alert(unavailableAlertTitle, isPresented: $showingUnavailableAlert) {
            if shouldOfferTranslationSettingsLink {
                Button(L("Open Settings")) {
                    model.languagePackManager?.openTranslationSettings()
                }
            }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(missingLanguagesMessage)
        }
        .onAppear {
            Task { @MainActor in
                await refreshRequiredLanguageStatuses()
            }
        }
    }

    private var requiredLanguagePairs: [LookupLanguagePair] {
        model.requiredLanguagePairsForCurrentSettings()
    }

    private var languageStatusProbePairs: [LookupLanguagePair] {
        let selectedLanguages = [sourceLanguage, targetLanguage]
        let commonLanguageIdentifiers = commonLanguages.map(\.id)
        let pairs = selectedLanguages.flatMap { selectedLanguage in
            commonLanguageIdentifiers.flatMap { commonLanguage in
                [
                    LookupLanguagePair.fixed(
                        sourceIdentifier: selectedLanguage,
                        targetIdentifier: commonLanguage
                    ),
                    LookupLanguagePair.fixed(
                        sourceIdentifier: commonLanguage,
                        targetIdentifier: selectedLanguage
                    ),
                ]
            }
        }
        var seenKeys = Set<String>()

        return pairs.filter { pair in
            guard !pair.isSameLanguage else { return false }
            return seenKeys.insert(pair.key).inserted
        }
    }

    private func selectedLanguageIdentifier(for role: LanguageRole) -> String {
        switch role {
        case .source:
            return sourceLanguage
        case .target:
            return targetLanguage
        }
    }

    private func languagePair(for role: LanguageRole, candidateIdentifier: String) -> LookupLanguagePair {
        switch role {
        case .source:
            return LookupLanguagePair.fixed(
                sourceIdentifier: candidateIdentifier,
                targetIdentifier: targetLanguage
            )
        case .target:
            return LookupLanguagePair.fixed(
                sourceIdentifier: sourceLanguage,
                targetIdentifier: candidateIdentifier
            )
        }
    }

    private func languagePackStatus(for role: LanguageRole) -> LanguageAvailability.Status? {
        languagePackStatus(for: selectedLanguageIdentifier(for: role))
    }

    private func languagePackStatus(for languageIdentifier: String) -> LanguageAvailability.Status? {
        if languageIdentifier == sourceLanguage && languageIdentifier == targetLanguage {
            return .installed
        }

        let statuses = languageStatusProbePairs.compactMap { pair -> LanguageAvailability.Status? in
            guard pair.sourceIdentifier == languageIdentifier || pair.targetIdentifier == languageIdentifier else {
                return nil
            }
            return getLanguagePackStatus(for: pair)
        }

        if statuses.contains(.installed) {
            return .installed
        }
        if statuses.contains(.supported) {
            return .supported
        }
        if statuses.contains(.unsupported) {
            return .unsupported
        }
        return nil
    }

    @ViewBuilder
    private func languageStatusIcon(for role: LanguageRole) -> some View {
        let status = languagePackStatus(for: role)

        if activeLanguageStatusRefreshCount > 0 {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        } else if status == nil {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        } else if status == .installed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
                .help(L("Language pack installed"))
        } else if let status {
            Button {
                Task { @MainActor in
                    await refreshRequiredLanguageStatuses(showLoading: true)
                }
            } label: {
                Image(systemName: status == .installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(status == .installed ? .green : .red)
            }
            .buttonStyle(.plain)
            .help(languagePackHelpText(for: status))
        }
    }

    private func refreshRequiredLanguageStatuses(showLoading: Bool = false) async {
        let pairsToRefresh = languageStatusProbePairs
        var requiredUnavailablePair: LookupLanguagePair?

        activeLanguageStatusRefreshCount += 1
        defer {
            activeLanguageStatusRefreshCount = max(0, activeLanguageStatusRefreshCount - 1)
        }

        for pair in pairsToRefresh where !pair.isSameLanguage {
            let status = await model.refreshLanguageAvailabilityStatus(
                from: pair.sourceIdentifier,
                to: pair.targetIdentifier,
                showLoading: false
            )
            if requiredLanguagePairs.contains(where: { $0.key == pair.key }),
               status != .installed,
               requiredUnavailablePair == nil {
                requiredUnavailablePair = pair
            }
        }

        if showLoading, let unavailablePair = requiredUnavailablePair {
            presentLanguageAvailabilityAlert(for: unavailablePair)
        } else if requiredUnavailablePair == nil {
            unavailablePair = nil
        }
    }

    private func getLanguagePackStatus(for pair: LookupLanguagePair) -> LanguageAvailability.Status? {
        guard !pair.isSameLanguage else { return .installed }
        return model.languagePackManager?.getStatus(
            from: pair.sourceIdentifier,
            to: pair.targetIdentifier
        )
    }

    private func menuItemStatus(for role: LanguageRole, candidateIdentifier: String) -> LanguageAvailability.Status? {
        let pair = languagePair(for: role, candidateIdentifier: candidateIdentifier)
        return getLanguagePackStatus(for: pair)
    }

    private func languageMenuLabel(for role: LanguageRole, language: (id: String, name: String)) -> String {
        if language.id == sourceLanguage && language.id == targetLanguage { return "● \(language.name)" }
        guard let status = menuItemStatus(for: role, candidateIdentifier: language.id) else { return "⋯ \(language.name)" }
        switch status {
        case .installed:   return "● \(language.name)"
        case .supported:   return "↓ \(language.name)"
        case .unsupported: return "✗ \(language.name)"
        @unknown default:  return "⋯ \(language.name)"
        }
    }

    private func languageName(for id: String) -> String {
        commonLanguages.first(where: { $0.id == id })?.name ?? id
    }

    private func languagePackHelpText(for status: LanguageAvailability.Status) -> String {
        switch status {
        case .installed:
            return L("Language pack installed")
        case .supported:
            return L("Language pack required - click to download")
        case .unsupported:
            return L("Translation not supported for this language pair.")
        @unknown default:
            return L("Translation not supported for this language pair.")
        }
    }

    private var shouldOfferTranslationSettingsLink: Bool {
        guard let unavailablePair,
              let status = getLanguagePackStatus(for: unavailablePair) else {
            return false
        }
        return status == .supported
    }

    private func presentLanguageAvailabilityAlert(for pair: LookupLanguagePair) {
        guard let status = getLanguagePackStatus(for: pair) else { return }

        unavailableAlertTitle = L("Language Pack Required")
        if status != .installed {
            unavailablePair = pair
            let sourceName = languageName(for: pair.sourceIdentifier)
            let targetName = languageName(for: pair.targetIdentifier)

            switch status {
            case .installed:
                return
            case .supported:
                missingLanguagesMessage = L("The language pack for \(sourceName) → \(targetName) translation is not installed. Please download the required language packs in System Settings > General > Language & Region > Translation Languages.")
            case .unsupported:
                missingLanguagesMessage = L("Translation not supported for this language pair.")
            @unknown default:
                missingLanguagesMessage = L("Translation not supported for this language pair.")
            }
            showingUnavailableAlert = true
        }
    }
}

// MARK: - App Language Picker

struct AppLanguagePickerRow: View {
    @Binding var language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("App Language"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text(L("Change the display language of the app"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - System Settings View

struct SystemSettingsView: View {
    @EnvironmentObject var model: AppModel
    var hidesScrollIndicator: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 0) {
                    ToggleRow(
                        title: L("Launch at Login"),
                        subtitle: L("Start automatically when you log in"),
                        isOn: $model.settings.launchAtLogin
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: L("Show Menu Bar Icon"),
                        subtitle: L("Display app icon in the status bar"),
                        isOn: $model.settings.showMenuBarIcon
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    MenuBarIconStylePickerRow(
                        style: $model.settings.menuBarIconStyle
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: L("Show Dock Icon"),
                        subtitle: L("Display app icon in the Dock"),
                        isOn: $model.settings.showDockIcon
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    AppLanguagePickerRow(
                        language: $model.settings.appLanguage
                    )
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
            }
            .padding()
            .background(
                ScrollViewScrollerConfigurator(
                    hidesVerticalScroller: hidesScrollIndicator
                )
            )
        }
        .scrollIndicators(hidesScrollIndicator ? .hidden : .automatic, axes: .vertical)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MenuBarIconStylePickerRow: View {
    @Binding var style: MenuBarIconStyle

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Menu Bar Icon Style"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text(L("Choose automatic, black, or white status bar icon rendering"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Picker("", selection: $style) {
                ForEach(MenuBarIconStyle.allCases) { iconStyle in
                    Text(iconStyle.displayName).tag(iconStyle)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
