import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsSectionCard(
                    title: "Shortcuts",
                    icon: "keyboard",
                    delay: 0
                ) {
                    SettingsRowView {
                        Text("Hotkey")
                            .foregroundStyle(.primary)
                        Spacer()
                        Picker("", selection: $model.settings.singleKey) {
                            ForEach(SingleKey.allCases) { key in
                                Text(key.title).tag(key)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(.accentColor)
                    }
                }

                SettingsSectionCard(
                    title: "Behavior",
                    icon: "gearshape",
                    delay: 0.05
                ) {
                    VStack(spacing: 14) {
                        SettingsToggleRow(
                            title: "Play pronunciation",
                            subtitle: "Audio playback after translation",
                            isOn: $model.settings.playPronunciation
                        )

                        Divider()
                            .opacity(0.5)

                        SettingsToggleRow(
                            title: "Launch at login",
                            subtitle: "Start automatically when you log in",
                            isOn: $model.settings.launchAtLogin
                        )
                    }
                }

                SettingsSectionCard(
                    title: "Permissions",
                    icon: "lock.shield",
                    delay: 0.1
                ) {
                    VStack(spacing: 14) {
                        PermissionRow(
                            title: "Screen Recording",
                            isGranted: model.permissions.status.screenRecording,
                            actionTitle: "Open Settings",
                            action: { model.permissions.requestAndOpenScreenRecording() }
                        )

                        Divider()
                            .opacity(0.5)

                        PermissionRow(
                            title: "Input Monitoring",
                            isGranted: model.permissions.status.inputMonitoring,
                            actionTitle: "Open Settings",
                            action: { model.permissions.requestAndOpenInputMonitoring() }
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
                                    Text("Refresh Status")
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
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let delay: Double
    @ViewBuilder let content: Content
    @State private var appeared = false

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
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(delay)) {
                appeared = true
            }
        }
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
            Text(isGranted ? "Granted" : "Not granted")
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
