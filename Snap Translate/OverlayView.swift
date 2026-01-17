import AppKit
import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var model: AppModel

    private var isVisible: Bool {
        if case .idle = model.overlayState { return false }
        return true
    }

    var body: some View {
        ZStack {
            if isVisible {
                overlayContent
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.overlayState {
            case .idle:
                EmptyView()

            case .loading(let word):
                loadingView(word: word)

            case .result(let content):
                resultView(content: content)

            case .error(let message):
                errorView(message: message)

            case .noWord:
                noWordView
            }
        }
        .frame(minWidth: 200, maxWidth: 420, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .inset(by: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.4),
                            .white.opacity(0.15),
                            .white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 12)
    }

    // MARK: - Loading View

    @ViewBuilder
    private func loadingView(word: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let word {
                Text(word)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Text("Translating")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                LoadingDotsView()
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    // MARK: - Result View

    @ViewBuilder
    private func resultView(content: OverlayContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Word + Phonetic
            headerSection(content: content)

            // Primary Translation
            primaryTranslationSection(content: content)

            // Definitions (if available)
            if !content.definitions.isEmpty {
                definitionsSection(definitions: content.definitions)
            }
        }
    }

    @ViewBuilder
    private func headerSection(content: OverlayContent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(content.word)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // 非持续模式下显示复制按钮
            if !model.settings.continuousTranslation {
                CopyButton(text: content.word)
            }

            if let phonetic = content.phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.secondary.opacity(0.1))
                    )
            }

            Spacer()

            // 非持续模式下显示关闭按钮
            if !model.settings.continuousTranslation {
                Button {
                    model.dismissOverlay()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func primaryTranslationSection(content: OverlayContent) -> some View {
        let targetIsEnglish = model.settings.targetLanguage.hasPrefix("en")
        let shouldHideTranslation = targetIsEnglish && !content.definitions.isEmpty
        
        if !shouldHideTranslation {
            HStack(spacing: 6) {
                if !content.definitions.isEmpty {
                    Text(content.translation)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                } else {
                    Text(content.translation)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                }

                if !model.settings.continuousTranslation {
                    CopyButton(text: content.translation)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, content.definitions.isEmpty ? 14 : 12)
        }
    }

    @ViewBuilder
    private func definitionsSection(definitions: [DictionaryEntry.Definition]) -> some View {
        let grouped = groupedTranslations(from: definitions)
        if grouped.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                        definitionGroupRow(partOfSpeech: group.0, translations: group.1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private func definitionGroupRow(partOfSpeech: String, translations: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !partOfSpeech.isEmpty {
                Text(displayedPartOfSpeech(for: partOfSpeech))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(posColor(for: partOfSpeech))
                    )
            }

            Text(translations.joined(separator: "；"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(2)
        }
    }

    private func displayedPartOfSpeech(for pos: String) -> String {
        let lowercased = pos.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lowercased {
        case "n", "noun":
            return "n."
        case "v", "verb":
            return "v."
        case "vt", "transitive verb":
            return "vt."
        case "vi", "intransitive verb":
            return "vi."
        case "adj", "adjective":
            return "adj."
        case "adv", "adverb":
            return "adv."
        case "prep", "preposition":
            return "prep."
        case "conj", "conjunction":
            return "conj."
        case "pron", "pronoun":
            return "pron."
        case "interj", "interjection":
            return "interj."
        default:
            return pos
        }
    }

    private func groupedTranslations(from definitions: [DictionaryEntry.Definition]) -> [(String, [String])] {
        var order: [String] = []
        var grouped: [String: [String]] = [:]

        for definition in definitions {
            guard let translation = definition.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translation.isEmpty else { continue }
            let key = definition.partOfSpeech
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
            }
            if grouped[key]?.contains(translation) == false {
                grouped[key]?.append(translation)
            }
        }

        return order.compactMap { key in
            guard let translations = grouped[key], !translations.isEmpty else { return nil }
            return (key, translations)
        }
    }

    private func posColor(for pos: String) -> Color {
        switch pos.lowercased() {
        case "n.", "n", "noun": return .blue
        case "v.", "v", "verb": return .green
        case "vt.", "vt", "transitive verb": return .green
        case "vi.", "vi", "intransitive verb": return .green
        case "adj.", "adj", "adjective": return .orange
        case "adv.", "adv", "adverb": return .purple
        case "prep.", "prep", "preposition": return .pink
        case "conj.", "conj", "conjunction": return .cyan
        case "pron.", "pron", "pronoun": return .teal
        case "interj.", "interj", "interjection": return .red
        default: return .gray
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    // MARK: - No Word View

    private var noWordView: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No word detected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
}

// MARK: - Loading Dots Animation

struct LoadingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            copyToClipboard(text)
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    copied = false
                }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(copied ? .green : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(copied ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Preview

#Preview {
    OverlayView()
        .environmentObject(AppModel(
            settings: SettingsStore(),
            permissions: PermissionManager()
        ))
        .frame(width: 500, height: 300)
        .background(.gray.opacity(0.3))
}
