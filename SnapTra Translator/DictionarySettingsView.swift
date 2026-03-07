//
//  DictionarySettingsView.swift
//  SnapTra Translator
//
//  Dictionary management tab with priority ordering.
//

import SwiftUI

/// Data model for dictionary sources
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Dictionary Priority"))
                    .font(.headline)
                Text(String(localized: "Drag the handle to reorder lookup priority. The first enabled dictionary will be queried first."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            // Dictionary Sources List - Using List for proper drag support on macOS
            List {
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
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove(perform: moveSource)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            loadSources()
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
                Label(String(localized: "Not installed"), systemImage: "icloud.and.arrow.down")
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
                    Text(String(localized: "Installing..."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

            case .installed(let sizeMB):
                Label(String(format: "%.0f MB", sizeMB), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)

            case .error(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "Installation failed"), systemImage: "exclamationmark.triangle.fill")
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
                Button(String(localized: "Download")) {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            case .downloading:
                Button(String(localized: "Cancel")) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

            case .installing:
                EmptyView()

            case .installed:
                Button(String(localized: "Uninstall")) {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)

            case .error:
                HStack(spacing: 8) {
                    Button(String(localized: "Retry")) {
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
            return String(localized: "Advanced offline dictionary")
        case .wordNet:
            return String(localized: "English definitions and synonyms")
        case .system:
            return String(localized: "macOS built-in dictionary")
        }
    }
}
