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
                // Sentence Translation Master Toggle
                SettingsToggleRow(
                    title: L("Enable Sentence Translation"),
                    subtitle: L("Double-click %@ to translate the paragraph under cursor", model.settings.hotkeyDisplayText),
                    isOn: $model.settings.sentenceTranslationEnabled
                )
                .padding(.horizontal)
                .padding(.top)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Sentence Translation Services"))
                        .font(.headline)
                    Text(L("Drag to reorder service priority. Enabled services will be shown in the paragraph translation panel."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

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

                // Name and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(source.type.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Toggle
                Toggle("", isOn: $source.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: source.isEnabled) { _, _ in
                        onToggle()
                    }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())

            // Bottom: Latency indicator (for non-native sources)
            if !source.isNative {
                Divider()
                    .padding(.vertical, 8)
                    .padding(.leading, 52)

                HStack {
                    Spacer()
                    latencyView
                }
                .padding(.leading, 52)
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
                .stroke(Color.accentColor.opacity(0.3), lineWidth: source.isNative ? 1.5 : 0)
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
        case .deepl:
            Image(systemName: "diamond.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.05, green: 0.24, blue: 0.63))
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
        case .failed:
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
        }
    }

    private func formattedLatency(_ ms: TimeInterval) -> String {
        if ms < 1000 {
            return String(format: "%.0f ms", ms)
        } else {
            return String(format: "%.1f s", ms / 1000)
        }
    }
}
