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
    case dictionary = "Dictionary"
    case sentence = "Sentence"
    case about = "About"
}

extension Notification.Name {
    static let switchSettingsTab = Notification.Name("switchSettingsTab")
}

enum SettingsWindowLayout {
    static let defaultContentWidth: CGFloat = 470
    static let dictionaryContentWidth: CGFloat = 740
    static let sentenceContentWidth: CGFloat = 450
    static let generalContentHeight: CGFloat = 590
    static let dictionaryContentHeight: CGFloat = 550
    static let sentenceContentHeight: CGFloat = 580
    static let aboutContentHeight: CGFloat = 520
    static let outerPadding: CGFloat = 16
    static let animationDuration: TimeInterval = 0.24

    static func contentWidth(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .dictionary:
            return dictionaryContentWidth
        case .sentence:
            return sentenceContentWidth
        default:
            return defaultContentWidth
        }
    }

    static func contentHeight(for tab: SettingsTab) -> CGFloat {
        switch tab {
        case .general:
            return generalContentHeight
        case .dictionary:
            return dictionaryContentHeight
        case .sentence:
            return sentenceContentHeight
        case .about:
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
                    Label(L("Dictionary"), systemImage: "books.vertical")
                }
                .tag(SettingsTab.dictionary)

            SentenceSettingsView(
                hidesScrollIndicator: hidesTabScrollIndicator
            )
                .tabItem {
                    Label(L("Sentence"), systemImage: "text.bubble")
                }
                .tag(SettingsTab.sentence)

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
        .onChange(of: selectedTab) { newValue in
            updateTabScrollIndicator(for: newValue, animated: true)
            resizeWindow(for: newValue, animated: true)
        }
        .onDisappear {
            scrollIndicatorResetWorkItem?.cancel()
        }
        .id(languageRefreshToken)
        .frame(
            width: SettingsWindowLayout.contentWidth(for: selectedTab),
            height: SettingsWindowLayout.contentHeight(for: selectedTab)
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

    private var allPermissionsGranted: Bool {
        model.permissions.status.screenRecording
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
        [
            .fixed(
                sourceIdentifier: model.settings.sourceLanguage,
                targetIdentifier: model.settings.targetLanguage
            )
        ]
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
            return allPermissionsGranted && targetLanguageReady
        }
        return allPermissionsGranted
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
                    }

                    ToggleRow(
                        title: L("Play Pronunciation"),
                        subtitle: L("Audio playback after translation"),
                        isOn: $model.settings.playPronunciation
                    )

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
                        title: L("Debug OCR Region"),
                        subtitle: L("Show capture area when shortcut is pressed"),
                        isOn: $model.settings.debugShowOcrRegion
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: L("Launch at Login"),
                        subtitle: L("Start automatically when you log in"),
                        isOn: $model.settings.launchAtLogin
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
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .secondary)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

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
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
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
    @State private var missingLanguagesMessage = ""

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
        ("vi", "Tiếng Việt")
    ]

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Translate to"))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            statusIcon

            Picker("", selection: $targetLanguage) {
                ForEach(commonLanguages, id: \.id) { lang in
                    Text(verbatim: lang.name).tag(lang.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .onChange(of: targetLanguage) { _, newValue in
                Task { @MainActor in
                    let status = await model.languagePackManager?.checkLanguagePair(
                        from: sourceLanguage,
                        to: newValue
                    )
                    if status != .installed {
                        checkLanguageAvailability(newValue)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .alert(L("Language Pack Required"), isPresented: $showingUnavailableAlert) {
            Button(L("Open Settings")) {
                model.languagePackManager?.openTranslationSettings()
            }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(missingLanguagesMessage)
        }
        .onAppear {
            Task { @MainActor in
                let status = await model.languagePackManager?.checkLanguagePair(
                    from: sourceLanguage,
                    to: targetLanguage
                )
                if status != .installed {
                    checkLanguageAvailability(targetLanguage)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        let isChecking = model.languagePackManager?.isChecking ?? false
        let isSameLanguage = sourceLanguage == targetLanguage ||
            (sourceLanguage.hasPrefix("en") && targetLanguage.hasPrefix("en")) ||
            (sourceLanguage.hasPrefix("zh") && targetLanguage.hasPrefix("zh"))
        let status = getLanguagePackStatus(targetLanguage)

        if isChecking {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        } else if isSameLanguage {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
                .help(L("Same language - no translation needed"))
        } else if let status = status {
            Button {
                Task { @MainActor in
                    let newStatus = await model.languagePackManager?.checkLanguagePair(
                        from: sourceLanguage,
                        to: targetLanguage
                    )
                    if newStatus != .installed {
                        checkLanguageAvailability(targetLanguage)
                    }
                }
            } label: {
                Image(systemName: status == .installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(status == .installed ? .green : .red)
            }
            .buttonStyle(.plain)
            .help(status == .installed
                  ? L("Language pack installed")
                  : L("Language pack required - click to download"))
        }
    }

    private func getLanguagePackStatus(_ language: String) -> LanguageAvailability.Status? {
        guard sourceLanguage != language else { return nil }
        return model.languagePackManager?.getStatus(from: sourceLanguage, to: language)
    }

    private func languageName(for id: String) -> String {
        commonLanguages.first(where: { $0.id == id })?.name ?? id
    }

    private func checkLanguageAvailability(_ language: String) {
        guard let status = getLanguagePackStatus(language) else { return }

        if status != .installed {
            let sourceName = languageName(for: sourceLanguage)
            let targetName = languageName(for: language)
            missingLanguagesMessage = L("The language pack for \(sourceName) → \(targetName) translation is not installed. Please download the required language packs in System Settings > General > Language & Region > Translation Languages.")
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
