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
                VStack(alignment: .leading, spacing: 12) {
                    if let word {
                        Text(word)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                        Text("Translating")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        LoadingDotsView()
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 18)

            case .result(let content):
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(content.word)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.65))

                        if let phonetic = content.phonetic, !phonetic.isEmpty {
                            Text(phonetic)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                    }

                    Text(content.translation)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 18)

            case .error(let message):
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .orange.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 18)

            case .noWord:
                HStack(spacing: 10) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("No word detected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
        .background(.regularMaterial)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .inset(by: 0.375)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.12),
                            .white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 32, x: 0, y: 16)
    }
}

struct LoadingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.8))
                    .frame(width: 3.5, height: 3.5)
                    .scaleEffect(animating ? 1.0 : 0.6)
                    .opacity(animating ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.12),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}
