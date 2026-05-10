import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LearningSettingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var learningService: LearningService
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var showingClearConfirmation = false
    @State private var showingCleanupConfirmation = false
    @State private var cleanupResultMessage: String?
    @State private var exportResultMessage: String?

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case pendingReview = "Pending"
        case mastered = "Mastered"

        var title: String {
            switch self {
            case .all: return L("All Words")
            case .pendingReview: return L("Pending Review")
            case .mastered: return L("Mastered")
            }
        }
    }

    init(modelContext: ModelContext) {
        _learningService = StateObject(wrappedValue: LearningService(modelContext: modelContext))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            cleanupSettingsSection
            statisticsCards
            searchAndFilterBar
            wordListView
        }
        .padding()
        .onAppear {
            Task {
                await learningService.refreshWords()
            }
        }
    }

    private var cleanupSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Auto Cleanup"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Toggle(L("Enable"), isOn: $model.settings.learningAutoCleanup)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L("Max Records:"))
                            .font(.caption)
                        TextField("", value: $model.settings.learningMaxRecords, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .controlSize(.small)
                    }

                    HStack(spacing: 8) {
                        Text(L("Cleanup Days:"))
                            .font(.caption)
                        TextField("", value: $model.settings.learningCleanupDays, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .controlSize(.small)
                    }
                }

                Spacer()

                Button {
                    showingCleanupConfirmation = true
                } label: {
                    Text(L("Cleanup Now"))
                        .font(.caption)
                }
                .controlSize(.small)
                .confirmationDialog(
                    L("Cleanup Old Records?"),
                    isPresented: $showingCleanupConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(L("Cleanup"), role: .destructive) {
                        Task {
                            let deleted = await learningService.cleanupOldRecords(
                                maxRecords: model.settings.learningMaxRecords,
                                cleanupDays: model.settings.learningCleanupDays
                            )
                            if deleted > 0 {
                                cleanupResultMessage = L("Deleted %lld records", deleted)
                            }
                        }
                    }
                    Button(L("Cancel"), role: .cancel) {}
                } message: {
                    Text(L("This will delete mastered words older than %lld days and remove excess records beyond %lld.", model.settings.learningCleanupDays, model.settings.learningMaxRecords))
                }
            }

            if let message = cleanupResultMessage {
                statusMessage(message, color: .green) {
                    cleanupResultMessage = nil
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Word Learning"))
                .font(.headline)
            Text(L("Track words you've looked up and review them with spaced repetition."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statisticsCards: some View {
        HStack(spacing: 12) {
            StatCard(
                title: L("Total Words"),
                value: learningService.totalWordCount,
                icon: "book.fill",
                color: .blue
            )

            StatCard(
                title: L("Pending Review"),
                value: learningService.pendingReviewCount,
                icon: "clock.fill",
                color: .orange
            )

            StatCard(
                title: L("Mastered"),
                value: learningService.masteredCount,
                icon: "checkmark.circle.fill",
                color: .green
            )
        }
    }

    private var searchAndFilterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L("Search words..."), text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                Picker("", selection: $filterMode) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    exportWords(format: .ankiTSV)
                } label: {
                    Label(L("Anki"), systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .disabled(filteredWords.isEmpty)
                .help(L("Export current words for Anki"))

                Button {
                    exportWords(format: .csv)
                } label: {
                    Text(L("CSV"))
                }
                .controlSize(.small)
                .disabled(filteredWords.isEmpty)
                .help(L("Export current words as CSV"))

                Button {
                    showingClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(L("Clear learning data"))
                .confirmationDialog(
                    L("Clear All Learning Data?"),
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(L("Clear All"), role: .destructive) {
                        Task {
                            await learningService.clearAllData()
                        }
                    }
                    Button(L("Cancel"), role: .cancel) {}
                } message: {
                    Text(L("This will delete all word records. This action cannot be undone."))
                }
            }

            if let message = exportResultMessage {
                statusMessage(message, color: message.hasPrefix(L("Export failed")) ? .red : .green) {
                    exportResultMessage = nil
                }
            }
        }
    }

    private var wordListView: some View {
        Group {
            if filteredWords.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredWords, id: \.word) { record in
                            WordRecordRow(
                                record: record,
                                onMarkMastered: {
                                    Task {
                                        await learningService.markAsMastered(record)
                                    }
                                },
                                onMarkReviewed: {
                                    Task {
                                        await learningService.markAsReviewed(record)
                                    }
                                },
                                onReset: {
                                    Task {
                                        await learningService.resetReview(record)
                                    }
                                },
                                onDelete: {
                                    Task {
                                        await learningService.deleteWord(record)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(L("No words yet"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(L("Words you look up will appear here. Hold the hotkey and move your cursor over English words to start learning."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredWords: [WordRecord] {
        var words: [WordRecord]
        switch filterMode {
        case .all:
            words = learningService.allWords
        case .pendingReview:
            words = learningService.pendingReviewWords
        case .mastered:
            words = learningService.masteredWords
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            words = words.filter { $0.word.contains(query) }
        }

        return words
    }

    private func exportWords(format: LearningExportFormat) {
        let rows = filteredWords.map { LearningExportRow(record: $0) }
        guard !rows.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = L("Export Learning Words")
        panel.nameFieldStringValue = "snaptra-learning-words.\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            let content = LearningExportService.export(rows: rows, format: format)
            try content.write(to: url, atomically: true, encoding: .utf8)
            exportResultMessage = L("Exported %lld words", rows.count)
        } catch {
            exportResultMessage = L("Export failed: %@", error.localizedDescription)
        }
    }

    private func statusMessage(_ message: String, color: Color, clear: @escaping () -> Void) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(color)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    clear()
                }
            }
    }
}

struct StatCard: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}

struct WordRecordRow: View {
    let record: WordRecord
    let onMarkMastered: () -> Void
    let onMarkReviewed: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.word)
                        .font(.system(size: 14, weight: .medium))

                    if record.isMastered {
                        Text(L("Mastered"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else if record.needsReview {
                        Text(L("Review"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }

                if let definitionText = record.definitionText,
                   !definitionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(definitionText.replacingOccurrences(of: "\n", with: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label("\(record.lookupCount)", systemImage: "eye.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let nextReview = record.nextReviewDate {
                        Label(formatReviewDate(nextReview), systemImage: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isHovered {
                actionButtons
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
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !record.isMastered {
                if record.needsReview {
                    Button {
                        onMarkReviewed()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help(L("Mark as reviewed"))
                }

                Button {
                    onMarkMastered()
                } label: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .help(L("Mark as mastered"))
            } else {
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help(L("Reset review progress"))
            }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(L("Delete"))
        }
    }

    private func formatReviewDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L("Today")
        } else if calendar.isDateInTomorrow(date) {
            return L("Tomorrow")
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }
}
