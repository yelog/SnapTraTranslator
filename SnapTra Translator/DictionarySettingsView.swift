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
    }
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
                Text(String(localized: "Drag to reorder lookup priority. The first enabled dictionary will be queried first."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Dictionary Sources List
            List {
                ForEach($sources) { $source in
                    DictionarySourceRow(source: $source) {
                        updateSources()
                    }
                }
                .onMove(perform: moveSource)
            }
            .listStyle(.inset)
            .frame(minHeight: 100)

            // ECDICT Download Section
            ECDICTDownloadSection(manager: model.dictionaryDownload) {
                // Callback when download starts - enable ECDICT source
                enableECDICTSource()
            }

            Spacer()
        }
        .padding()
        .onAppear {
            loadSources()
        }
    }

    private func enableECDICTSource() {
        // Find and enable the ECDICT source
        if let index = sources.firstIndex(where: { $0.type == .ecdict }) {
            sources[index].isEnabled = true
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

struct DictionarySourceRow: View {
    @Binding var source: DictionarySource
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon based on type
            Image(systemName: source.type == .ecdict ? "book.fill" : "text.book.closed")
                .font(.system(size: 16))
                .foregroundStyle(source.type == .ecdict ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(size: 13, weight: .medium))
                Text(source.type == .ecdict
                     ? String(localized: "Advanced offline dictionary")
                     : String(localized: "macOS built-in dictionary"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $source.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: source.isEnabled) { _, _ in
                    onToggle()
                }
        }
        .padding(.vertical, 4)
    }
}

struct ECDICTDownloadSection: View {
    @ObservedObject var manager: DictionaryDownloadManager
    var onDownloadStart: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Advanced English Dictionary"))
                        .font(.system(size: 14, weight: .medium))
                    Text(String(localized: "ECDICT - Comprehensive offline dictionary"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusView
            }

            if case .error(let message) = manager.state {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
            }
        }
        .padding()
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
    }

    @ViewBuilder
    private var statusView: some View {
        switch manager.state {
        case .notInstalled:
            Button(String(localized: "Download")) {
                onDownloadStart?()
                manager.startDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 60)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(String(localized: "Cancel")) {
                    manager.cancelDownload()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
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
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(format: "%.1f MB", sizeMB))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button(String(localized: "Delete")) {
                    manager.delete()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
            }

        case .error:
            Button(String(localized: "Retry")) {
                onDownloadStart?()
                manager.retry()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
