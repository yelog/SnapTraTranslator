//
//  DictionarySettingsView.swift
//  SnapTra Translator
//
//  Dictionary management tab with priority ordering.
//

import SwiftUI

struct TTSServiceRow: View {
    let provider: TTSProvider
    let isSelected: Bool
    let latency: TTSLatencyTester.LatencyResult
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .overlay {
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    }
                }
            
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            latencyView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
    
    private var iconName: String {
        switch provider {
        case .apple: return "speaker.wave.2.fill"
        case .youdao: return "globe.asia.australia.fill"
        case .bing: return "magnifyingglass.circle.fill"
        case .google: return "book.fill"
        case .baidu: return "speaker.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch provider {
        case .apple: return .secondary
        case .youdao: return .red
        case .bing: return .blue
        case .google: return .green
        case .baidu: return .blue
        }
    }
    
    private var subtitleText: String {
        switch provider {
        case .apple: return L("Offline local service")
        case .youdao: return L("No token required, supports UK/US accent")
        case .bing: return L("Best quality, WebSocket based")
        case .google: return L("Good quality, requires signature")
        case .baidu: return L("No token required, supports UK/US accent")
        }
    }
    
    @ViewBuilder
    private var latencyView: some View {
        switch latency {
        case .pending:
            Text("--")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        case .testing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .offline:
            Text(L("Local"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                )
        case .success(let ms):
            Text(formattedLatency(ms))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(ms < 500 ? .green : (ms < 1000 ? .orange : .red))
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

struct DictionarySource: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: SourceType
    var isEnabled: Bool

    enum SourceType: String, Codable {
        case system    // macOS system dictionary
        case ecdict    // ECDICT offline dictionary
        case wordNet   // WordNet English-English dictionary
    }
}

// MARK: - Common Download State

/// Common download state shared between different download managers
enum DownloadState: Equatable {
    case notInstalled
    case downloading(progress: Double)
    case installing
    case installed(sizeMB: Double)
    case error(String)
}

struct DictionarySettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var sources: [DictionarySource] = []
    @StateObject private var ttsTester = TTSLatencyTester()
    @State private var hasTestedTTS = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dictionarySection
                
                Divider()
                    .padding(.horizontal)
                
                ttsSection
            }
        }
        .onAppear {
            loadSources()
            if !hasTestedTTS {
                hasTestedTTS = true
                Task { await ttsTester.testAllProviders() }
            }
        }
    }
    
    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Dictionary Priority"))
                    .font(.headline)
                Text(L("Drag the handle to reorder lookup priority. The first enabled dictionary will be queried first."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            VStack(spacing: 8) {
                ForEach($sources) { $source in
                    IntegratedDictionaryRow(
                        source: $source,
                        downloadState: downloadState(for: source.type),
                        onToggle: { updateSources() },
                        onDownloadComplete: { handleDownloadComplete(for: source.type) },
                        onDelete: {
                            performDelete(for: source.type)
                            handleDelete(for: source.type)
                        },
                        onDownload: { performDownload(for: source.type) },
                        onCancel: { performCancel(for: source.type) },
                        onRetry: { performRetry(for: source.type) }
                    )
                }
                .onMove(perform: moveSource)
            }
            .padding(.horizontal)
        }
    }
    
    private var ttsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Pronunciation Service"))
                    .font(.headline)
                Text(L("Apple is the offline local service, others require network. If a third-party service fails, it will automatically fallback to Apple local service."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)

            VStack(spacing: 6) {
                ForEach(TTSProvider.allCases) { provider in
                    TTSServiceRow(
                        provider: provider,
                        isSelected: model.settings.ttsProvider == provider,
                        latency: ttsTester.latencies[provider] ?? .pending,
                        onSelect: { model.settings.ttsProvider = provider }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal)

            // English Accent Selection (only for third-party services)
            if model.settings.ttsProvider != .apple {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("English Accent"))
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.settings.englishAccent },
                            set: { newValue in
                                DispatchQueue.main.async {
                                    model.settings.englishAccent = newValue
                                }
                            }
                        )) {
                            ForEach(EnglishAccent.allCases) { accent in
                                Text(accent.displayName).tag(accent)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )
                    .padding(.horizontal)
                    
                    Text(L("Apple uses system voice and does not support accent selection"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await ttsTester.testAllProviders() }
                } label: {
                    HStack(spacing: 6) {
                        if ttsTester.isTesting {
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
                .disabled(ttsTester.isTesting)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Private Helpers

    private func downloadState(for type: DictionarySource.SourceType) -> DownloadState? {
        switch type {
        case .ecdict:
            return convertState(model.dictionaryDownload.state)
        case .wordNet:
            return convertState(model.wordNetDownload.state)
        case .system:
            return nil
        }
    }

    private func convertState(_ state: DictionaryDownloadManager.State) -> DownloadState {
        switch state {
        case .notInstalled: return .notInstalled
        case .downloading(let progress): return .downloading(progress: progress)
        case .installing: return .installing
        case .installed(let sizeMB): return .installed(sizeMB: sizeMB)
        case .error(let message): return .error(message)
        }
    }

    private func convertState(_ state: WordNetDownloadManager.State) -> DownloadState {
        switch state {
        case .notInstalled: return .notInstalled
        case .downloading(let progress): return .downloading(progress: progress)
        case .installing: return .installing
        case .installed(let sizeMB): return .installed(sizeMB: sizeMB)
        case .error(let message): return .error(message)
        }
    }

    private func performDownload(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.startDownload()
        case .wordNet:
            model.wordNetDownload.startDownload()
        case .system:
            break
        }
    }

    private func performCancel(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.cancelDownload()
        case .wordNet:
            model.wordNetDownload.cancelDownload()
        case .system:
            break
        }
    }

    private func performDelete(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.delete()
        case .wordNet:
            model.wordNetDownload.delete()
        case .system:
            break
        }
    }

    private func performRetry(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.retry()
        case .wordNet:
            model.wordNetDownload.retry()
        case .system:
            break
        }
    }

    private func handleDownloadComplete(for type: DictionarySource.SourceType) {
        if let index = sources.firstIndex(where: { $0.type == type }) {
            sources[index].isEnabled = true
            updateSources()
        }
    }

    private func handleDelete(for type: DictionarySource.SourceType) {
        if let index = sources.firstIndex(where: { $0.type == type }) {
            sources[index].isEnabled = false
            updateSources()
        }
    }

    private func loadSources() {
        sources = model.settings.dictionarySources
    }

    private func updateSources() {
        model.settings.dictionarySources = sources
    }

    private func moveSource(from indices: IndexSet, to offset: Int) {
        sources.move(fromOffsets: indices, toOffset: offset)
        updateSources()
    }
}

// MARK: - Integrated Dictionary Row

struct IntegratedDictionaryRow: View {
    @Binding var source: DictionarySource
    var downloadState: DownloadState?
    var onToggle: () -> Void
    var onDownloadComplete: () -> Void
    var onDelete: () -> Void
    var onDownload: () -> Void
    var onCancel: () -> Void
    var onRetry: () -> Void

    @State private var previousState: DownloadState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: Drag handle + Icon + Name + Toggle (single row)
            HStack(spacing: 12) {
                // Drag handle (aligned with first row)
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)

                // Icon
                iconView
                    .frame(width: 24)

                // Name and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Toggle
                Toggle("", isOn: $source.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!isInstalled)
                    .onChange(of: source.isEnabled) { _, _ in
                        onToggle()
                    }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())

            // Bottom: Download management (for downloadable dictionaries)
            if needsDownloadManagement {
                Divider()
                    .padding(.vertical, 8)
                    .padding(.leading, 52) // Align with content (drag handle + icon + spacing)

                downloadManagementBar
                    .padding(.leading, 52) // Align with content
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
        .onChange(of: downloadState) { oldState, newState in
            // Detect download completion
            if let oldState = oldState, let newState = newState {
                if case .installing = oldState, case .installed = newState {
                    onDownloadComplete()
                }
            }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var iconView: some View {
        switch source.type {
        case .ecdict:
            Image(systemName: "book.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
        case .wordNet:
            Image(systemName: "character.book.closed")
                .font(.system(size: 16))
                .foregroundStyle(.purple)
        case .system:
            Image(systemName: "text.book.closed")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var downloadManagementBar: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator

            Spacer()

            // Action buttons
            actionButtons
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if let state = downloadState {
            switch state {
            case .notInstalled:
                Label(L("Not installed"), systemImage: "icloud.and.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .downloading(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

            case .installing:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(L("Installing..."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

            case .installed(let sizeMB):
                Label(String(format: "%.0f MB", sizeMB), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)

            case .error(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Label(L("Installation failed"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let state = downloadState {
            switch state {
            case .notInstalled:
                Button(L("Download")) {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            case .downloading:
                Button(L("Cancel")) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .installing:
                EmptyView()

            case .installed:
                Button(L("Uninstall")) {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)

            case .error:
                HStack(spacing: 8) {
                    Button(L("Retry")) {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Private Properties

    private var needsDownloadManagement: Bool {
        source.type == .ecdict || source.type == .wordNet
    }

    private var isInstalled: Bool {
        guard let state = downloadState else { return true }
        if case .installed = state { return true }
        return false
    }

    private var subtitleText: String {
        switch source.type {
        case .ecdict:
            return L("Advanced offline dictionary")
        case .wordNet:
            return L("English definitions and synonyms")
        case .system:
            return L("macOS built-in dictionary")
        }
    }
}
