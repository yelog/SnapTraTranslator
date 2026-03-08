//
//  SettingsWindowView.swift
//  SnapTra Translator
//
//  Settings window with tabbed interface (General, Dictionary, About).
//

import SwiftUI
import Translation

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case dictionary = "Dictionary"
    case about = "About"
}

extension Notification.Name {
    static let switchSettingsTab = Notification.Name("switchSettingsTab")
}

struct SettingsWindowView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab: SettingsTab
    @State private var languageRefreshToken = UUID()
    var initialTab: SettingsTab = .general

    init(initialTab: SettingsTab = .general) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label(L("General"), systemImage: "gear")
                }
                .tag(SettingsTab.general)

            DictionarySettingsView()
                .tabItem {
                    Label(L("Dictionary"), systemImage: "books.vertical")
                }
                .tag(SettingsTab.dictionary)

            AboutSettingsView()
                .tabItem {
                    Label(L("About"), systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchSettingsTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            // Force refresh when language changes
            languageRefreshToken = UUID()
        }
        .id(languageRefreshToken)
        .frame(width: 370, height: 620)
        .padding()
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var appeared = false

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
        switch model.settings.translationMode {
        case .fixedDirection:
            return [
                .fixed(
                    sourceIdentifier: model.settings.sourceLanguage,
                    targetIdentifier: model.settings.targetLanguage
                )
            ]
        case .autoMutualChineseEnglish:
            let chineseIdentifier = model.settings.autoTranslateChineseIdentifier
            return [
                .automatic(direction: .englishToChinese, chineseIdentifier: chineseIdentifier),
                .automatic(direction: .chineseToEnglish, chineseIdentifier: chineseIdentifier),
            ]
        }
    }

    @available(macOS 15.0, *)
    private func refreshLanguageStatuses() async {
        guard let manager = model.languagePackManager else { return }
        for pair in requiredLanguagePairs where !pair.isSameLanguage {
            _ = await manager.checkLanguagePair(from: pair.sourceIdentifier, to: pair.targetIdentifier)
        }
    }

    @available(macOS 15.0, *)
    private func normalizeAutomaticTranslationSettings() {
        model.settings.sourceLanguage = "en"
        if !model.settings.targetLanguage.hasPrefix("zh") {
            model.settings.targetLanguage = "zh-Hans"
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
                        TranslationModePickerRow(
                            mode: $model.settings.translationMode,
                            onModeChanged: {
                                if model.settings.translationMode == .autoMutualChineseEnglish {
                                    normalizeAutomaticTranslationSettings()
                                }
                                Task { @MainActor in
                                    await refreshLanguageStatuses()
                                }
                            }
                        )

                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.5)

                        if model.settings.translationMode == .fixedDirection {
                            GeneralTranslationLanguageRow(
                                targetLanguage: $model.settings.targetLanguage,
                                sourceLanguage: $model.settings.sourceLanguage
                            )
                        } else {
                            AutoTranslationChineseVariantRow(
                                chineseLanguage: $model.settings.targetLanguage
                            )

                            Divider()
                                .padding(.horizontal, 14)
                                .opacity(0.5)

                            DefaultLookupDirectionRow(
                                direction: $model.settings.defaultLookupDirection
                            )
                        }

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
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task { @MainActor in
                await model.permissions.refreshStatusAsync()
                if #available(macOS 15.0, *) {
                    if model.settings.translationMode == .autoMutualChineseEnglish {
                        normalizeAutomaticTranslationSettings()
                    }
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
struct TranslationModePickerRow: View {
    @Binding var mode: TranslationMode
    let onModeChanged: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Translation Mode"))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            Picker("", selection: $mode) {
                ForEach(TranslationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .onChange(of: mode) { _, _ in
                onModeChanged()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

@available(macOS 15.0, *)
struct DefaultLookupDirectionRow: View {
    @Binding var direction: LookupDirection

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Default Direction"))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            Picker("", selection: $direction) {
                ForEach(LookupDirection.allCases) { direction in
                    Text(direction.title).tag(direction)
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

@available(macOS 15.0, *)
struct AutoTranslationChineseVariantRow: View {
    @Binding var chineseLanguage: String
    @EnvironmentObject var model: AppModel
    @State private var showingUnavailableAlert = false
    @State private var missingLanguagesMessage = ""

    private let chineseVariants: [(id: String, nameKey: String)] = [
        ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)"),
    ]

    private var currentPairs: [LookupLanguagePair] {
        [
            .automatic(direction: .englishToChinese, chineseIdentifier: chineseLanguage),
            .automatic(direction: .chineseToEnglish, chineseIdentifier: chineseLanguage),
        ]
    }

    private var currentStatuses: [LanguageAvailability.Status] {
        currentPairs.compactMap { pair in
            model.languagePackManager?.getStatus(from: pair.sourceIdentifier, to: pair.targetIdentifier)
        }
    }

    private var allInstalled: Bool {
        currentStatuses.count == currentPairs.count && currentStatuses.allSatisfy { $0 == .installed }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(L("Chinese Variant"))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            statusIcon

            Picker("", selection: $chineseLanguage) {
                ForEach(chineseVariants, id: \.id) { variant in
                    Text(LocalizedStringKey(variant.nameKey)).tag(variant.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .onChange(of: chineseLanguage) { _, _ in
                Task { @MainActor in
                    await refreshStatuses()
                    if !allInstalled {
                        showAvailabilityAlert()
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
    }

    @ViewBuilder
    private var statusIcon: some View {
        if model.languagePackManager?.isChecking == true {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        } else if allInstalled {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
                .help(L("Language pack installed"))
        } else {
            Button {
                Task { @MainActor in
                    await refreshStatuses()
                    if !allInstalled {
                        showAvailabilityAlert()
                    }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(L("Language pack required - click to download"))
        }
    }

    private func refreshStatuses() async {
        guard let manager = model.languagePackManager else { return }
        for pair in currentPairs {
            _ = await manager.checkLanguagePair(from: pair.sourceIdentifier, to: pair.targetIdentifier)
        }
    }

    private func showAvailabilityAlert() {
        let sourceName = languageName(for: chineseLanguage)
        missingLanguagesMessage = L("The language packs for English ↔ \(sourceName) translation are not fully installed. Please download the required language packs in System Settings > General > Language & Region > Translation Languages.")
        showingUnavailableAlert = true
    }

    private func languageName(for id: String) -> String {
        guard let key = chineseVariants.first(where: { $0.id == id })?.nameKey else {
            return id
        }
        return L(key)
    }
}

@available(macOS 15.0, *)
struct GeneralTranslationLanguageRow: View {
    @Binding var targetLanguage: String
    @Binding var sourceLanguage: String
    @EnvironmentObject var model: AppModel
    @State private var showingUnavailableAlert = false
    @State private var missingLanguagesMessage = ""

    private let commonLanguages: [(id: String, nameKey: String)] = [
        ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)"),
        ("en", "English"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("fr", "French"),
        ("de", "German"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("ar", "Arabic"),
        ("th", "Thai"),
        ("vi", "Vietnamese")
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
                    Text(LocalizedStringKey(lang.nameKey)).tag(lang.id)
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
        guard let key = commonLanguages.first(where: { $0.id == id })?.nameKey else {
            return id
        }
        return L(key)
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
