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
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func primaryTranslationSection(content: OverlayContent) -> some View {
        if !content.definitions.isEmpty {
            // 如果有详细定义，显示简洁的主翻译
            Text(content.translation)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        } else {
            // 没有详细定义时，显示更大的翻译
            Text(content.translation)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func definitionsSection(definitions: [DictionaryEntry.Definition]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(definitions.enumerated()), id: \.offset) { index, def in
                    definitionRow(definition: def, index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func definitionRow(definition: DictionaryEntry.Definition, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // 词性标签
                if !definition.partOfSpeech.isEmpty {
                    Text(definition.partOfSpeech)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(posColor(for: definition.partOfSpeech))
                        )
                }

                // 翻译
                if let translation = definition.translation {
                    Text(translation)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                }
            }

            // 英文释义
            Text(definition.meaning)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .lineLimit(3)

            // 例句
            if let example = definition.examples.first {
                HStack(alignment: .top, spacing: 4) {
                    Text("▸")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(example)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .italic()
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }
        }
    }

    private func posColor(for pos: String) -> Color {
        switch pos.lowercased() {
        case "n.", "noun": return .blue
        case "v.", "verb": return .green
        case "adj.", "adjective": return .orange
        case "adv.", "adverb": return .purple
        case "prep.", "preposition": return .pink
        case "conj.", "conjunction": return .cyan
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
