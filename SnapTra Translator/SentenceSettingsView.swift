//
//  SentenceSettingsView.swift
//  SnapTra Translator
//
//  Sentence translation services management with priority ordering.
//

import AppKit
import SwiftUI

struct SentenceSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var sources: [SentenceTranslationSource] = []
    @StateObject private var latencyTester = SentenceLatencyTester()
    @State private var hasTestedLatency = false
    var hidesScrollIndicator: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Sentence Translation Services"))
                        .font(.headline)
                    Text(L("Drag to reorder service priority. Enabled services will be shown in the paragraph translation panel."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)

                ReorderableVStack(items: $sources, content: { source, index in
                    SentenceServiceRow(
                        source: source,
                        latency: latencyTester.latencies[source.wrappedValue.type] ?? .pending,
                        onToggle: { updateSources() }
                    )
                }, onMove: moveSource)
                .padding(.horizontal)

                // Refresh latency button
                HStack {
                    Spacer()
                    Button {
                        Task { await latencyTester.testAll() }
                    } label: {
                        HStack(spacing: 6) {
                            if latencyTester.isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Text(L("Refresh Latency"))
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
                    .disabled(latencyTester.isTesting)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(
                ScrollViewScrollerConfigurator(
                    hidesVerticalScroller: hidesScrollIndicator
                )
            )
        }
        .scrollIndicators(hidesScrollIndicator ? .hidden : .automatic, axes: .vertical)
        .onAppear {
            loadSources()
            if !hasTestedLatency {
                hasTestedLatency = true
                Task { await latencyTester.testAll() }
            }
        }
    }

    private func loadSources() {
        sources = model.settings.sentenceTranslationSources
    }

    private func updateSources() {
        model.settings.sentenceTranslationSources = sources
    }

    private func moveSource(from indices: IndexSet, to offset: Int) {
        sources.move(fromOffsets: indices, toOffset: offset)
        updateSources()
    }
}

// MARK: - Sentence Service Row

struct SentenceServiceRow: View {
    @Binding var source: SentenceTranslationSource
    var latency: SentenceLatencyTester.LatencyResult
    var onToggle: () -> Void
    @StateObject private var localizationManager = LocalizationManager.shared

    private var isNativeUnavailable: Bool {
        if source.isNative {
            if #available(macOS 15.0, *) {
                return false
            }
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: Drag handle + Icon + Name + Toggle (single row)
            HStack(spacing: 12) {
                // Drag handle
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)

                // Icon
                iconView
                    .frame(width: 24)

                // Name and description - use L() for real-time localization
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(localizedDisplayName)
                            .font(.system(size: 13, weight: .medium))

                        // Latency indicator (for non-native sources)
                        if !source.isNative {
                            latencyView
                        }
                    }
                    Text(localizedSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .id("lang-\(localizationManager.currentLanguage.rawValue)-\(source.type.rawValue)")

                Spacer()

                // Toggle
                Toggle("", isOn: $source.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(isNativeUnavailable)
                    .onChange(of: source.isEnabled) { _, _ in
                        onToggle()
                    }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())

            // Unavailable warning for native translation on macOS 14
            if isNativeUnavailable {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(L("Requires macOS 15 or later"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
        // Special styling for native translation
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(isNativeUnavailable ? 0 : 0.3), lineWidth: source.isNative ? 1.5 : 0)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch source.type {
        case .native:
            Image(systemName: "apple.logo")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
        case .google:
            Image("TTSGoogle")
                .resizable()
                .interpolation(.high)
        case .bing:
            Image("TTSBing")
                .resizable()
                .interpolation(.high)
        case .youdao:
            Image("TTSYoudao")
                .resizable()
                .interpolation(.high)
        }
    }

    @ViewBuilder
    private var latencyView: some View {
        switch latency {
        case .pending:
            Text("--")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(L("Testing"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)
        case .local:
            Text(L("Local"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                )
                .frame(width: 60)
        case .success(let ms):
            Text(formattedLatency(ms))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ms < 500 ? .green : (ms < 1000 ? .orange : .red))
                .frame(width: 60, alignment: .trailing)
        case .failed(let message):
            Text(L("Failed"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.1))
                )
                .frame(width: 60)
                .overlay(
                    TooltipView(text: message ?? L("Translation failed"))
                )
        }
    }

    private func formattedLatency(_ ms: TimeInterval) -> String {
        if ms < 1000 {
            return String(format: "%.0f ms", ms)
        } else {
            return String(format: "%.1f s", ms / 1000)
        }
    }

    // Localized display name that responds to language changes
    private var localizedDisplayName: String {
        switch source.type {
        case .native:
            return L("Native Translation")
        case .google:
            return L("Google Translate")
        case .bing:
            return L("Bing Translate")
        case .youdao:
            return L("Youdao Translate")
        }
    }

    // Localized subtitle that responds to language changes
    private var localizedSubtitle: String {
        switch source.type {
        case .native:
            return L("System Translation")
        case .google:
            return L("Google web translation")
        case .bing:
            return L("Bing web translation")
        case .youdao:
            return L("Youdao web translation")
        }
    }
}

// MARK: - Tooltip Support

private struct TooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = TooltipNSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

private class TooltipNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        // Pass through mouse events to views below
        super.mouseDown(with: event)
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return false
    }
}
