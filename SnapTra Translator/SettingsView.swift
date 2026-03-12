import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - General
                SettingsSectionCard(
                    title: L("General"),
                    icon: "gear"
                ) {
                    VStack(spacing: 14) {
                        // App Language Selector
                        LanguageSelectorRow(
                            title: L("App Language"),
                            subtitle: L("Change the display language of the app"),
                            selection: $model.settings.appLanguage
                        )

                        Divider()
                            .opacity(0.5)

                        SettingsToggleRow(
                            title: L("Launch at login"),
                            subtitle: L("Start automatically when you log in"),
                            isOn: $model.settings.launchAtLogin
                        )
                    }
                }

                // MARK: - Shortcuts
                SettingsSectionCard(
                    title: L("Shortcuts"),
                    icon: "keyboard"
                ) {
                    SettingsRowView {
                        HotkeyKeycapSelector(selectedKey: $model.settings.singleKey)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // MARK: - Translation
                SettingsSectionCard(
                    title: L("Translation"),
                    icon: "character.book.closed"
                ) {
                    VStack(spacing: 14) {
                        SettingsToggleRow(
                            title: L("Continuous translation"),
                            subtitle: L("Keep translating as mouse moves"),
                            isOn: $model.settings.continuousTranslation
                        )

                        Divider()
                            .opacity(0.5)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Pronunciation"))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.primary)
                                Text(L("Auto-play after translation"))
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
                    }
                }

                // MARK: - Dictionary
                SettingsSectionCard(
                    title: L("Dictionary"),
                    icon: "books.vertical"
                ) {
                    ECDICTDictionaryRow(manager: model.dictionaryDownload)
                }

                // MARK: - Permissions
                SettingsSectionCard(
                    title: L("Permissions"),
                    icon: "lock.shield"
                ) {
                    VStack(spacing: 14) {
                        PermissionRow(
                            title: L("Screen Recording"),
                            isGranted: model.permissions.status.screenRecording,
                            actionTitle: L("Open Settings"),
                            action: { model.permissions.requestAndOpenScreenRecording() }
                        )

                        Divider()
                            .opacity(0.5)

                        HStack {
                            Spacer()
                            Button {
                                Task { await model.permissions.refreshStatusAsync() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .medium))
                                    Text(L("Refresh Status"))
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.quaternary)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task { await model.permissions.refreshStatusAsync() }
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

struct SettingsRowView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .font(.system(size: 13))
    }
}

struct HotkeyKeycapSelector: View {
    @Binding var selectedKey: SingleKey

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                button(for: SingleKey.leftShift)

                Text(L("Hotkey"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)

                button(for: SingleKey.rightShift)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    button(for: SingleKey.fn)
                    button(for: SingleKey.leftControl)
                    button(for: SingleKey.leftOption)
                    button(for: SingleKey.leftCommand)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    button(for: SingleKey.rightCommand)
                    button(for: SingleKey.rightOption)
                    button(for: SingleKey.rightControl)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(for key: SingleKey) -> some View {
        Button {
            selectedKey = key
        } label: {
            HotkeyKeycapButton(
                symbol: symbol(for: key),
                tooltip: tooltip(for: key),
                isSelected: selectedKey == key
            )
        }
        .buttonStyle(.plain)
    }

    private func symbol(for key: SingleKey) -> String {
        switch key {
        case .leftShift, .rightShift:
            return "⇧"
        case .leftControl, .rightControl:
            return "⌃"
        case .leftOption, .rightOption:
            return "⌥"
        case .leftCommand, .rightCommand:
            return "⌘"
        case .fn:
            return "Fn"
        }
    }

    private func tooltip(for key: SingleKey) -> String {
        switch key {
        case .leftShift:
            return L("Left Shift")
        case .rightShift:
            return L("Right Shift")
        case .leftControl:
            return L("Left Control")
        case .rightControl:
            return L("Right Control")
        case .leftOption:
            return L("Left Option")
        case .rightOption:
            return L("Right Option")
        case .leftCommand:
            return L("Left Command")
        case .rightCommand:
            return L("Right Command")
        case .fn:
            return "Fn"
        }
    }
}

private struct HotkeyKeycapButton: View {
    let symbol: String
    let tooltip: String
    let isSelected: Bool

    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverWorkItem: DispatchWorkItem?

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                if showTooltip {
                    Text(tooltip)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        )
                        .offset(y: -26)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .onHover { hovering in
                isHovering = hovering
                hoverWorkItem?.cancel()
                if hovering {
                    let workItem = DispatchWorkItem {
                        if isHovering {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showTooltip = true
                            }
                        }
                    }
                    hoverWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
                } else {
                    showTooltip = false
                }
            }
    }
}


struct SettingsToggleRow: View {
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
    }
}

struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isGranted ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .shadow(color: isGranted ? .green.opacity(0.4) : .orange.opacity(0.4), radius: 3, x: 0, y: 0)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text(isGranted ? L("Granted") : L("Not granted"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isGranted ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isGranted ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                )
            if !isGranted {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isGranted)
    }
}

// MARK: - Dictionary Section

struct ECDICTDictionaryRow: View {
    @ObservedObject var manager: DictionaryDownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(L("Advanced English Dictionary"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(L("Powered by ECDICT"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.08))
                            )
                    }
                    Text(statusLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Used first for English word lookups. Translation still uses Apple Translation."))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        DictionaryBenefitPill(title: L("Fuller definitions"))
                        DictionaryBenefitPill(title: L("Tech terms"))
                        DictionaryBenefitPill(title: L("Works offline"))
                    }
                }
                Spacer()
                actionView
            }

            if case .downloading(let progress) = manager.state {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Cancel")) { manager.cancelDownload() }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if case .error(let message) = manager.state {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(L("Retry")) { manager.retry() }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button(L("Choose file…")) { manager.selectManually() }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var statusLine: String {
        switch manager.state {
        case .notInstalled:
            return L("Get a larger offline dictionary for fuller meanings and better technical terms.")
        case .downloading:
            return L("Downloading the advanced dictionary…")
        case .installing:
            return L("Installing the advanced dictionary…")
        case .installed(let sizeMB):
            return String(
                format: L("Enabled · %.0f MB stored offline"),
                sizeMB
            )
        case .error:
            return L("Advanced dictionary installation failed")
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch manager.state {
        case .notInstalled:
            Button(L("Install")) { manager.startDownload() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

        case .downloading:
            EmptyView()

        case .installing:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .controlSize(.small)
                Text(L("Installing"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

        case .installed:
            HStack(spacing: 8) {
                Text(L("Enabled"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.12))
                    )
                Button(L("Remove")) { manager.delete() }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

        case .error:
            EmptyView()
        }
    }
}

private struct DictionaryBenefitPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.08))
            )
    }
}

// MARK: - Language Selector Row

struct LanguageSelectorRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: AppLanguage
    @State private var isHovering = false

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

            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        selection = language
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .font(.system(size: 13))
                            if selection == language {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary.opacity(isHovering ? 0.7 : 0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
                )
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140)
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }
}
