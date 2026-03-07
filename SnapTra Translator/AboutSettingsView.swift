//
//  AboutSettingsView.swift
//  SnapTra Translator
//
//  About tab for the settings window.
//

import SwiftUI

struct AboutSettingsView: View {
    @EnvironmentObject var model: AppModel

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

            // App Name
            Text("SnapTra Translator")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            // Version
            Text(appVersion)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)

            // Description
            Text(String(localized: "Move your cursor over a word and press the shortcut to translate"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            // Links
            HStack(spacing: 20) {
                LinkButton(
                    title: "Twitter",
                    url: URL(string: "https://x.com/yelogeek")!
                )
                LinkButton(
                    title: "GitHub",
                    url: URL(string: "https://github.com/yelog/SnapTraTranslator")!
                )
                LinkButton(
                    title: String(localized: "Website"),
                    url: URL(string: "https://snaptra.yelog.org/")!
                )
            }

            Spacer()

            // Check for Updates Button
            Button(String(localized: "Check for Updates")) {
                checkForUpdates()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func checkForUpdates() {
        // Placeholder for update checking functionality
        // This could open the App Store or a website
        if let url = URL(string: "https://apps.apple.com/") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct LinkButton: View {
    let title: String
    let url: URL

    var body: some View {
        Button(title) {
            NSWorkspace.shared.open(url)
        }
        .buttonStyle(.link)
    }
}

// MARK: - About View (for separate window from menu)

struct AboutView: View {
    @EnvironmentObject var model: AppModel

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

            // App Name
            Text("SnapTra Translator")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            // Version
            Text(appVersion)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)

            // Description
            Text(String(localized: "Move your cursor over a word and press the shortcut to translate"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            // Links
            HStack(spacing: 16) {
                LinkButton(
                    title: "Twitter",
                    url: URL(string: "https://x.com/yelogeek")!
                )
                LinkButton(
                    title: "GitHub",
                    url: URL(string: "https://github.com/yelog/SnapTraTranslator")!
                )
            }

            Spacer()
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}
