import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LearningSettingsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var learningService: LearningService
    let hidesScrollIndicator: Bool
    @State private var searchText = ""
    @State private var filterMode: LearningWordFilter = .all
    @State private var sourceLanguageFilter: String?
    @State private var showingClearConfirmation = false
    @State private var showingCleanupConfirmation = false
    @State private var showingCleanupSettings = false
    @State private var cleanupResultMessage: String?
    @State private var exportResultMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(modelContext: ModelContext, hidesScrollIndicator: Bool = false) {
        _learningService = StateObject(wrappedValue: LearningService(modelContext: modelContext))
        self.hidesScrollIndicator = hidesScrollIndicator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            searchAndFilterBar
            wordListView
        }
        .onAppear {
            Task {
                await reloadWords()
                await Task.yield()
                await learningService.refreshSummaryCounts()
                await Task.yield()
                await learningService.refreshAvailableLanguageIdentifiers()
            }
        }
        .onChange(of: searchText) { _, _ in
            scheduleSearchReload()
        }
        .onChange(of: filterMode) { _, _ in
            reloadWordsImmediately()
        }
        .onChange(of: sourceLanguageFilter) { _, _ in
            reloadWordsImmediately()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .sheet(isPresented: $showingCleanupSettings) {
            cleanupSettingsSheet
        }
        .confirmationDialog(
            L("Cleanup Old Records?"),
            isPresented: $showingCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("Cleanup"), role: .destructive) {
                cleanupOldRecords()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This will delete mastered words older than %lld days and remove excess records beyond %lld.", model.settings.learningCleanupDays, model.settings.learningMaxRecords))
        }
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

    private var cleanupSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Auto Cleanup"))
                        .font(.headline)
                    Text(L("This will delete mastered words older than %lld days and remove excess records beyond %lld.", model.settings.learningCleanupDays, model.settings.learningMaxRecords))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L("Close")) {
                    showingCleanupSettings = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            cleanupToggle

            HStack(alignment: .bottom, spacing: 16) {
                cleanupFields
                Spacer()
                cleanupNowButton
            }

            if let message = cleanupResultMessage {
                statusMessage(message, color: .green) {
                    cleanupResultMessage = nil
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var cleanupToggle: some View {
        Toggle(L("Enable"), isOn: $model.settings.learningAutoCleanup)
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private var cleanupFields: some View {
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
    }

    private var cleanupNowButton: some View {
        Button {
            presentCleanupConfirmation()
        } label: {
            Text(L("Cleanup Now"))
                .font(.caption)
        }
        .controlSize(.small)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Word Learning"))
                    .font(.headline)
                Text(L("Track words you've looked up and review them with spaced repetition."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            managementMenu
        }
    }

    private var searchAndFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                searchAndFilterControlsRow
                searchAndFilterControlsStack
            }

            filterPicker

            if let message = exportResultMessage {
                statusMessage(message, color: message.hasPrefix(L("Export failed")) ? .red : .green) {
                    exportResultMessage = nil
                }
            }

            if let message = cleanupResultMessage, !showingCleanupSettings {
                statusMessage(message, color: .green) {
                    cleanupResultMessage = nil
                }
            }
        }
    }

    private var searchAndFilterControlsRow: some View {
        HStack(spacing: 12) {
            searchField
                .frame(minWidth: 220, maxWidth: .infinity)

            languagePicker
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var searchAndFilterControlsStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
                .frame(maxWidth: .infinity)

            languagePicker
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchField: some View {
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
    }

    private var filterPicker: some View {
        Picker("", selection: $filterMode) {
            ForEach(LearningWordFilter.allCases, id: \.self) { mode in
                Text(filterTitle(for: mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var languagePicker: some View {
        Picker(L("Language"), selection: $sourceLanguageFilter) {
            Text(L("All Languages")).tag(String?.none)
            ForEach(learningService.availableLanguageIdentifiers, id: \.self) { identifier in
                Text(LearningLanguageDisplay.name(for: identifier)).tag(Optional(identifier))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 130)
    }

    private var managementMenu: some View {
        Menu {
            Menu(L("Export")) {
                Button {
                    exportWords(format: .plainText)
                } label: {
                    Label(L("TXT"), systemImage: "doc.text")
                }

                Button {
                    exportWords(format: .ankiTSV)
                } label: {
                    Label(L("Anki"), systemImage: "square.and.arrow.up")
                }

                Button {
                    exportWords(format: .csv)
                } label: {
                    Label(L("CSV"), systemImage: "tablecells")
                }
            }
            .disabled(learningService.visibleRows.isEmpty)

            Divider()

            Button {
                showingCleanupSettings = true
            } label: {
                Label(L("Auto Cleanup"), systemImage: "clock.arrow.circlepath")
            }

            Button {
                presentCleanupConfirmation()
            } label: {
                Label(L("Cleanup Now"), systemImage: "trash.slash")
            }

            Divider()

            Button(role: .destructive) {
                showingClearConfirmation = true
            } label: {
                Label(L("Clear learning data"), systemImage: "trash")
            }
        } label: {
            Label(L("Manage"), systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func filterTitle(for mode: LearningWordFilter) -> String {
        let count: Int
        switch mode {
        case .all:
            count = learningService.totalWordCount
        case .pendingReview:
            count = learningService.pendingReviewCount
        case .mastered:
            count = learningService.masteredCount
        }
        return "\(mode.title) \(count)"
    }

    private var wordListView: some View {
        Group {
            if learningService.visibleRows.isEmpty {
                if learningService.isLoadingPage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyStateView
                }
            } else {
                List {
                    ForEach(learningService.visibleRows) { row in
                        wordRow(for: row)
                            .equatable()
                            .onAppear {
                                requestNextPageIfNeeded(after: row)
                            }
                    }

                    if learningService.isLoadingPage {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .scrollIndicators(hidesScrollIndicator ? .hidden : .automatic, axes: .vertical)
                .background(
                    ScrollViewScrollerConfigurator(
                        hidesVerticalScroller: hidesScrollIndicator
                    )
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func wordRow(for row: WordRecordRowModel) -> WordRecordRow {
        WordRecordRow(
            row: row,
            onMarkMastered: {
                guard let record = learningService.wordRecord(for: row.id) else { return }
                Task {
                    await learningService.markAsMastered(record)
                }
            },
            onMarkReviewed: {
                guard let record = learningService.wordRecord(for: row.id) else { return }
                Task {
                    await learningService.markAsReviewed(record)
                }
            },
            onReset: {
                guard let record = learningService.wordRecord(for: row.id) else { return }
                Task {
                    await learningService.resetReview(record)
                }
            },
            onDelete: {
                guard let record = learningService.wordRecord(for: row.id) else { return }
                Task {
                    await learningService.deleteWord(record)
                }
            }
        )
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

    private func requestNextPageIfNeeded(after row: WordRecordRowModel) {
        guard row.id == paginationTriggerRowID else { return }
        Task {
            await learningService.loadMoreWords()
        }
    }

    private var paginationTriggerRowID: String? {
        guard learningService.hasMoreWords,
              !learningService.isLoadingPage,
              !learningService.visibleRows.isEmpty else {
            return nil
        }

        let triggerIndex = max(learningService.visibleRows.count - 10, 0)
        return learningService.visibleRows[triggerIndex].id
    }

    private func reloadWords() async {
        await learningService.reloadWords(
            filter: filterMode,
            searchText: searchText,
            sourceLanguageIdentifier: sourceLanguageFilter
        )
    }

    private func scheduleSearchReload() {
        searchTask?.cancel()
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await reloadWords()
        }
    }

    private func reloadWordsImmediately() {
        searchTask?.cancel()
        Task {
            await reloadWords()
        }
    }

    private func cleanupOldRecords() {
        Task {
            let deleted = await learningService.cleanupOldRecords(
                maxRecords: model.settings.learningMaxRecords,
                cleanupDays: model.settings.learningCleanupDays
            )
            cleanupResultMessage = L("Deleted %lld records", deleted)
        }
    }

    private func presentCleanupConfirmation() {
        guard showingCleanupSettings else {
            showingCleanupConfirmation = true
            return
        }

        showingCleanupSettings = false
        DispatchQueue.main.async {
            showingCleanupConfirmation = true
        }
    }

    private func exportWords(format: LearningExportFormat) {
        Task {
            let rows = await learningService.exportRows(
                filter: filterMode,
                searchText: searchText,
                sourceLanguageIdentifier: sourceLanguageFilter
            )
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

struct WordRecordRowModel: Identifiable, Equatable {
    let id: String
    let word: String
    let sourceLanguageName: String
    let definitionText: String?
    let lookupCount: Int
    let reviewDateText: String?
    let isMastered: Bool
    let needsReview: Bool

    init(record: WordRecord, now: Date) {
        id = record.word
        word = record.word
        sourceLanguageName = LearningLanguageDisplay.name(for: record.sourceLanguageIdentifier)
        definitionText = record.definitionText?
            .replacingOccurrences(of: "\n", with: " · ")
        lookupCount = record.lookupCount
        reviewDateText = Self.formatReviewDate(record.nextReviewDate)
        isMastered = record.isMastered
        needsReview = !record.isMastered && (record.nextReviewDate ?? .distantFuture) <= now
    }

    private static func formatReviewDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L("Today")
        } else if calendar.isDateInTomorrow(date) {
            return L("Tomorrow")
        } else {
            return reviewDateFormatter.string(from: date)
        }
    }

    private static let reviewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
}

struct WordRecordRow: View, Equatable {
    let row: WordRecordRowModel
    let onMarkMastered: () -> Void
    let onMarkReviewed: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    static func == (lhs: WordRecordRow, rhs: WordRecordRow) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.word)
                        .font(.system(size: 14, weight: .medium))

                    Text(row.sourceLanguageName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    if row.isMastered {
                        Text(L("Mastered"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    } else if row.needsReview {
                        Text(L("Review"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if let definitionText = row.definitionText,
                   !definitionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(definitionText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    Label("\(row.lookupCount)", systemImage: "eye.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let reviewDateText = row.reviewDateText {
                        Label(reviewDateText, systemImage: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if row.needsReview {
                    Button {
                        onMarkReviewed()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help(L("Mark as reviewed"))
                    .accessibilityLabel(L("Mark as reviewed"))
                }

                Menu {
                    actionMenuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("More"))
                .accessibilityLabel(L("More"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            actionMenuItems
        }
    }

    @ViewBuilder
    private var actionMenuItems: some View {
        if !row.isMastered {
            if row.needsReview {
                Button {
                    onMarkReviewed()
                } label: {
                    Label(L("Mark as reviewed"), systemImage: "checkmark.circle")
                }
            }

            Button {
                onMarkMastered()
            } label: {
                Label(L("Mark as mastered"), systemImage: "star")
            }
        } else {
            Button {
                onReset()
            } label: {
                Label(L("Reset review progress"), systemImage: "arrow.counterclockwise")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label(L("Delete"), systemImage: "trash")
        }
    }
}
