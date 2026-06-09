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
                        settings: model.settings,
                        latency: latencyTester.latencies[source.wrappedValue.type] ?? .pending,
                        onToggle: { updateSources() },
                        onConfigurationChange: refreshLatencyState
                    )
                }, onMove: moveSource)
                .padding(.horizontal)

                // Refresh latency button
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await latencyTester.testAll(
                                sources: sources,
                                configurations: model.settings.llmProviderConfigurations
                            )
                        }
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
                Task {
                    await latencyTester.testAll(
                        sources: sources,
                        configurations: model.settings.llmProviderConfigurations
                    )
                }
            }
        }
    }

    private func loadSources() {
        sources = model.settings.sentenceTranslationSources
    }

    private func updateSources() {
        model.settings.sentenceTranslationSources = sources
    }

    private func refreshLatencyState() {
        for source in sources where source.type.isLLMProvider {
            latencyTester.latencies[source.type] = .pending
        }
    }

    private func moveSource(from indices: IndexSet, to offset: Int) {
        sources.move(fromOffsets: indices, toOffset: offset)
        updateSources()
    }
}

// MARK: - Sentence Service Row

struct SentenceServiceRow: View {
    @Binding var source: SentenceTranslationSource
    @ObservedObject var settings: SettingsStore
    var latency: SentenceLatencyTester.LatencyResult
    var onToggle: () -> Void
    var onConfigurationChange: () -> Void
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var apiKeyText = ""

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

                        if showsMissingAPIKeyBadge {
                            missingAPIKeyBadge
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
                        loadAPIKey()
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

            if source.type.isLLMProvider && source.isEnabled {
                llmConfigurationView
                    .padding(.top, 8)
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
        .onAppear {
            loadAPIKey()
        }
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
        case .openAI:
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.teal)
        case .anthropic:
            Image(systemName: "brain.head.profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.purple)
        case .gemini:
            Image(systemName: "diamond")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
        case .deepSeek:
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.cyan)
        case .zhipu:
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.indigo)
        case .ollama:
            Image(systemName: "desktopcomputer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
        case .omlx:
            Image(systemName: "cpu")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
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
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        case .deepSeek:
            return "DeepSeek"
        case .zhipu:
            return "智谱"
        case .ollama:
            return "Ollama"
        case .omlx:
            return "oMLX"
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
        case .openAI:
            return L("OpenAI API translation")
        case .anthropic:
            return L("Claude API translation")
        case .gemini:
            return L("Gemini API translation")
        case .deepSeek:
            return L("DeepSeek API translation")
        case .zhipu:
            return L("Zhipu API translation")
        case .ollama:
            return L("Local Ollama translation")
        case .omlx:
            return L("Local oMLX translation")
        }
    }

    @ViewBuilder
    private var llmConfigurationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.leading, 52)

            llmFieldRow(title: L("Model")) {
                TextField(
                    source.type.defaultLLMModel,
                    text: Binding(
                        get: {
                            settings.llmProviderConfiguration(for: source.type).model
                        },
                        set: { model in
                            let configuration = settings.llmProviderConfiguration(for: source.type)
                            settings.updateLLMProviderConfiguration(
                                for: source.type,
                                model: model,
                                baseURL: configuration.baseURL
                            )
                            onConfigurationChange()
                        }
                    )
                )
            }

            if source.type == .zhipu {
                llmFieldRow(title: L("Region")) {
                    Picker(
                        "",
                        selection: Binding(
                            get: {
                                settings.llmProviderConfiguration(for: source.type).zhipuRegion ?? .domestic
                            },
                            set: { region in
                                let configuration = settings.llmProviderConfiguration(for: source.type)
                                settings.updateLLMProviderConfiguration(
                                    for: source.type,
                                    model: configuration.model,
                                    baseURL: region.defaultBaseURL,
                                    zhipuRegion: region
                                )
                                onConfigurationChange()
                            }
                        )
                    ) {
                        ForEach(ZhipuAPIRegion.allCases, id: \.self) { region in
                            Text(region.displayName).tag(region)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            llmFieldRow(title: L("Base URL")) {
                TextField(
                    source.type.defaultLLMBaseURL,
                    text: Binding(
                        get: {
                            settings.llmProviderConfiguration(for: source.type).baseURL
                        },
                        set: { baseURL in
                            let configuration = settings.llmProviderConfiguration(for: source.type)
                            settings.updateLLMProviderConfiguration(
                                for: source.type,
                                model: configuration.model,
                                baseURL: baseURL
                            )
                            onConfigurationChange()
                        }
                    )
                )
            }

            if source.type.requiresAPIKey || source.type.acceptsOptionalAPIKey {
                llmFieldRow(title: source.type.requiresAPIKey ? L("API Key") : L("API Key Optional")) {
                    SecureField(
                        source.type.requiresAPIKey ? L("Required") : L("Optional"),
                        text: $apiKeyText
                    )
                    .onChange(of: apiKeyText) { _, newValue in
                        LLMProviderCredentialStore.setAPIKey(newValue, for: source.type)
                        onConfigurationChange()
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    settings.resetLLMProviderConfiguration(for: source.type)
                    onConfigurationChange()
                } label: {
                    Label(L("Reset Defaults"), systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 52)
        }
    }

    private func llmFieldRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            content()
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
        .padding(.leading, 52)
    }

    private var showsMissingAPIKeyBadge: Bool {
        source.isEnabled
            && source.type.requiresAPIKey
            && !LLMProviderCredentialStore.hasAPIKey(for: source.type)
    }

    private var missingAPIKeyBadge: some View {
        Text(L("API Key Required"))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.12))
            )
    }

    private func loadAPIKey() {
        apiKeyText = LLMProviderCredentialStore.apiKey(for: source.type) ?? ""
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
