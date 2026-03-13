//
//  AboutSettingsView.swift
//  SnapTra Translator
//
//  About tab for the settings window.
//

import SwiftUI

// MARK: - Shared version helper

private func appVersionString() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    return "v\(version)"
}

private func openAppStore() {
    if let url = URL(string: "https://apps.apple.com/cn/app/snaptra-translator/id6757981764") {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - About Settings Tab

struct AboutSettingsView: View {
    @EnvironmentObject var model: AppModel
    var hidesScrollIndicator: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App Identity
                AppIdentityHeader()
                    .padding(.top, 4)

                // GitHub Star CTA
                GitHubStarCard()

                // Links Card
                VStack(spacing: 0) {
                    AboutLinkRow(
                        icon: "globe",
                        iconColor: .blue,
                        title: L("Website"),
                        url: URL(string: "https://snaptra.yelog.org/")!
                    )
                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)
                    AboutLinkRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        iconColor: .primary,
                        title: "GitHub",
                        url: URL(string: "https://github.com/yelog/SnapTraTranslator")!
                    )
                    Divider()
                        .padding(.horizontal, 14)
                        .opacity(0.5)
                    AboutLinkRow(
                        icon: "at",
                        iconColor: .cyan,
                        title: "Twitter / X",
                        url: URL(string: "https://x.com/yelogeek")!
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

                // Check for Updates
                Button {
                    openAppStore()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12, weight: .medium))
                        Text(L("Check for Updates"))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                // Copyright
                Text("© 2025 yelog. All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 4)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - About View (for separate window from menu)

struct AboutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            AppIdentityHeader()

            GitHubStarCard()

            HStack(spacing: 12) {
                LinkButton(
                    icon: "globe",
                    title: L("Website"),
                    url: URL(string: "https://snaptra.yelog.org/")!
                )
                LinkButton(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "GitHub",
                    url: URL(string: "https://github.com/yelog/SnapTraTranslator")!
                )
                LinkButton(
                    icon: "at",
                    title: "Twitter / X",
                    url: URL(string: "https://x.com/yelogeek")!
                )
            }

            Spacer()
        }
        .padding()
        .frame(width: 380, height: 340)
    }
}

// MARK: - Shared Sub-components

struct AppIdentityHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)

            Text("SnapTra Translator")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(appVersionString())
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(L("Move your cursor over a word and press the shortcut to translate"))
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
        }
    }
}

struct GitHubStarCard: View {
    var body: some View {
        Button {
            if let url = URL(string: "https://github.com/yelog/SnapTraTranslator") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow)
                    Text(L("Star on GitHub"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(L("If SnapTra helps you, a ⭐ on GitHub means a lot!"))
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.yellow.opacity(0.08))
                    .shadow(color: .yellow.opacity(0.08), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AboutLinkRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LinkButton: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}
