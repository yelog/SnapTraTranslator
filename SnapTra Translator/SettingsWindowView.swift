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
    var initialTab: SettingsTab = .general

    init(initialTab: SettingsTab = .general) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label(String(localized: "General"), systemImage: "gear")
                }
                .tag(SettingsTab.general)

            DictionarySettingsView()
                .tabItem {
                    Label(String(localized: "Dictionary"), systemImage: "books.vertical")
                }
                .tag(SettingsTab.dictionary)

            AboutSettingsView()
                .tabItem {
                    Label(String(localized: "About"), systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchSettingsTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
        .frame(width: 400, height: 480)
        .padding()
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var appeared = false

    private var allPermissionsGranted: Bool {
        model.permissions.status.screenRecording
    }

    @available(macOS 15.0, *)
    private var targetLanguageReady: Bool {
        guard let status = model.languagePackManager?.getStatus(
            from: model.settings.sourceLanguage,
            to: model.settings.targetLanguage
        ) else {
            return false
        }
        return status == .installed
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
                        title: String(localized: "Screen Recording"),
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
                        title: String(localized: "Play Pronunciation"),
                        subtitle: String(localized: "Audio playback after translation"),
                        isOn: $model.settings.playPronunciation
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: String(localized: "Continuous Translation"),
                        subtitle: String(localized: "Keep translating as mouse moves"),
                        isOn: $model.settings.continuousTranslation
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: String(localized: "Launch at Login"),
                        subtitle: String(localized: "Start automatically when you log in"),
                        isOn: $model.settings.launchAtLogin
                    )

                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)

                    ToggleRow(
                        title: String(localized: "Debug OCR Region"),
                        subtitle: String(localized: "Show capture area when shortcut is pressed"),
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
                            Text(String(localized: "Ready to translate"))
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
                                _ = await model.languagePackManager?.checkLanguagePair(
                                    from: model.settings.sourceLanguage,
                                    to: model.settings.targetLanguage
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text(String(localized: "Refresh"))
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
            Task { await model.permissions.refreshStatusAsync() }
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

                    Text(isGranted ? String(localized: "Granted") : String(localized: "Required"))
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
            Text(String(localized: "Translate to"))
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
        .alert(String(localized: "Language Pack Required"), isPresented: $showingUnavailableAlert) {
            Button(String(localized: "Open Settings")) {
                model.languagePackManager?.openTranslationSettings()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
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
                .help(String(localized: "Same language - no translation needed"))
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
                  ? String(localized: "Language pack installed")
                  : String(localized: "Language pack required - click to download"))
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
        return String(localized: String.LocalizationValue(key))
    }

    private func checkLanguageAvailability(_ language: String) {
        guard let status = getLanguagePackStatus(language) else { return }

        if status != .installed {
            let sourceName = languageName(for: sourceLanguage)
            let targetName = languageName(for: language)
            missingLanguagesMessage = String(localized: "The language pack for \(sourceName) → \(targetName) translation is not installed. Please download the required language packs in System Settings > General > Language & Region > Translation Languages.")
            showingUnavailableAlert = true
        }
    }
}
