//
//  ContentView.swift
//  Snap Translate
//
//  Created by 杨玉杰 on 2026/1/12.
//

import SwiftUI
import Translation

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var appeared = false

    private var allPermissionsGranted: Bool {
        model.permissions.status.screenRecording && model.permissions.status.inputMonitoring
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
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.8)

                Text("Snap Translate")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)

                Text("Move your cursor over a word and press the shortcut")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 4)
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                ContentPermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    isGranted: model.permissions.status.screenRecording,
                    action: { model.permissions.requestAndOpenScreenRecording() }
                )

                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)

                ContentPermissionRow(
                    icon: "keyboard",
                    title: "Input Monitoring",
                    isGranted: model.permissions.status.inputMonitoring,
                    action: { model.permissions.requestAndOpenInputMonitoring() }
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
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            VStack(spacing: 0) {
                HotkeyKeycapSelector(selectedKey: $model.settings.singleKey)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play pronunciation")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                        Text("Audio playback after translation")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.settings.playPronunciation)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continuous translation")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                        Text("Keep translating as mouse moves")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.settings.continuousTranslation)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                        Text("Start automatically when you log in")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()
                    .padding(.horizontal, 14)
                    .opacity(0.5)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debug OCR region")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                        Text("Show capture area when shortcut is pressed")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.settings.debugShowOcrRegion)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
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
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            if #available(macOS 15.0, *) {
                LanguagePickerSection(
                    sourceLanguage: $model.settings.sourceLanguage,
                    targetLanguage: $model.settings.targetLanguage
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
            }

            HStack(spacing: 12) {
                if allReady {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                        Text("Ready to translate")
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
                            let status = await model.languagePackManager?.checkLanguagePair(
                                from: model.settings.sourceLanguage,
                                to: model.settings.targetLanguage
                            )
                            // 检查后如果未安装，提示用户
                            if status != .installed {
                                // 这里会触发 LanguagePickerSection 的检测和弹窗
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Refresh")
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
            .opacity(appeared ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: allReady)
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task { await model.permissions.refreshStatusAsync() }
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }
}

struct ContentPermissionRow: View {
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

                    Text(isGranted ? "Granted" : "Required")
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

@available(macOS 15.0, *)
struct LanguagePickerSection: View {
    @Binding var sourceLanguage: String
    @Binding var targetLanguage: String
    @EnvironmentObject var model: AppModel
    @State private var showingUnavailableAlert = false
    @State private var unavailableLanguageName = ""

    private let commonLanguages: [(id: String, name: String)] = [
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
        mainContent
            .alert("Language Pack Required", isPresented: $showingUnavailableAlert) {
                Button("Open Settings") {
                    model.languagePackManager?.openTranslationSettings()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The language pack for \(unavailableLanguageName) is not installed. Please download it in System Settings > General > Language & Region > Translation Languages.")
            }
            .onAppear {
                // 应用打开时立即检测当前 Target Language
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

    private var mainContent: some View {
        VStack(spacing: 0) {
            sourceLanguageRow
            Divider()
                .padding(.horizontal, 14)
                .opacity(0.5)
            targetLanguageRow
        }
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var sourceLanguageRow: some View {
        HStack(spacing: 12) {
            Text("Source Language")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
            Spacer()
            Picker("", selection: $sourceLanguage) {
                ForEach(commonLanguages, id: \.id) { lang in
                    Text(lang.name).tag(lang.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.accentColor)
            .disabled(true)
            .opacity(0.6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var targetLanguageRow: some View {
        HStack(spacing: 12) {
            Text("Target Language")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            statusIcon

            Picker("", selection: $targetLanguage) {
                ForEach(commonLanguages, id: \.id) { lang in
                    Text(lang.name).tag(lang.id)
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
    }

    @ViewBuilder
    private var statusIcon: some View {
        let isChecking = model.languagePackManager?.isChecking ?? false
        let status = getLanguagePackStatus(targetLanguage)

        if isChecking {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
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
            .help(status == .installed ? "Language pack installed" : "Click to check and download")
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.background)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 0.5)
    }

    @ViewBuilder
    private func languageOptionView(for lang: (id: String, name: String)) -> some View {
        Text(lang.name).tag(lang.id)
    }

    private func getLanguagePackStatus(_ language: String) -> LanguageAvailability.Status? {
        guard sourceLanguage != language else { return nil }
        return model.languagePackManager?.getStatus(from: sourceLanguage, to: language)
    }

    private func checkLanguageAvailability(_ language: String) {
        guard let status = getLanguagePackStatus(language) else { return }

        if status != .installed {
            unavailableLanguageName = commonLanguages.first(where: { $0.id == language })?.name ?? language
            showingUnavailableAlert = true
        }
    }
}
