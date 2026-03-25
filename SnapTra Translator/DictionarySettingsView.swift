//
//  DictionarySettingsView.swift
//  SnapTra Translator
//
//  Dictionary management tab with priority ordering.
//

import AppKit
import SwiftUI

struct TTSServiceRow: View {
    let provider: TTSProvider
    let isSelected: Bool
    let latency: TTSLatencyTester.LatencyResult
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            selectionButton(isSelected: isSelected, action: onSelect)

            providerIcon
                .frame(width: 24, height: 24)

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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func selectionButton(isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .overlay {
                    if isSelected {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch provider {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        case .youdao:
            Image("TTSYoudao")
                .resizable()
                .interpolation(.high)
        case .bing:
            Image("TTSBing")
                .resizable()
                .interpolation(.high)
        case .google:
            Image("TTSGoogle")
                .resizable()
                .interpolation(.high)
        case .baidu:
            Image("TTSBaidu")
                .resizable()
                .interpolation(.high)
        }
    }

    private var subtitleText: String {
        provider.description
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

struct DictionarySource: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: SourceType
    var isEnabled: Bool

    static func == (lhs: DictionarySource, rhs: DictionarySource) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.type == rhs.type && lhs.isEnabled == rhs.isEnabled
    }

    enum SourceType: String, Codable {
        case system
        case ecdict
    }

    var displayName: String {
        type.displayName
    }
}

extension DictionarySource.SourceType {
    var displayName: String {
        switch self {
        case .ecdict:
            return L("Advanced Dictionary")
        case .system:
            return L("System Dictionary")
        }
    }

    var subtitle: String {
        switch self {
        case .ecdict:
            return L("Advanced offline dictionary")
        case .system:
            return L("macOS built-in dictionary")
        }
    }

    var needsDownloadManagement: Bool {
        self == .ecdict
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
    @State private var sentenceSources: [SentenceTranslationSource] = []
    @StateObject private var ttsTester = TTSLatencyTester()
    @StateObject private var sentenceLatencyTester = SentenceLatencyTester()
    @State private var hasTestedTTS = false
    @State private var hasTestedSentence = false
    @State private var selectedTab: DictionaryTab = .dictionary
    var hidesScrollIndicator: Bool = false

    enum DictionaryTab: String, CaseIterable {
        case dictionary
        case sentence
        case wordPronunciation
        case sentencePronunciation
        case learning

        var title: String {
            switch self {
            case .dictionary: return L("Word")
            case .sentence: return L("Sentence")
            case .learning: return L("Learning")
            case .wordPronunciation: return L("Word Pronunciation")
            case .sentencePronunciation: return L("Sentence Pronunciation")
            }
        }

        var icon: String {
            switch self {
            case .dictionary: return "books.vertical"
            case .sentence: return "text.bubble"
            case .learning: return "graduationcap"
            case .wordPronunciation: return "speaker.wave.2"
            case .sentencePronunciation: return "megaphone"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leftSidebar
                .frame(width: 190)

            Divider()

            rightContent
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            loadSources()
            loadSentenceSources()
            if !hasTestedTTS {
                hasTestedTTS = true
                Task { await ttsTester.testAllProviders() }
            }
            if !hasTestedSentence {
                hasTestedSentence = true
                Task { await sentenceLatencyTester.testAll() }
            }
        }
    }

    private var leftSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            sidebarButton(for: .dictionary)
            sidebarButton(for: .sentence)
            Divider()
                .padding(.vertical, 4)
            sidebarButton(for: .wordPronunciation)
            sidebarButton(for: .sentencePronunciation)
            Divider()
                .padding(.vertical, 4)
            sidebarButton(for: .learning)
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func sidebarButton(for tab: DictionaryTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }

    @ViewBuilder
    private var rightContent: some View {
        ScrollView {
            Group {
                switch selectedTab {
                case .dictionary:
                    dictionarySection
                case .sentence:
                    sentenceTranslationSection
                case .learning:
                    learningSection
                case .wordPronunciation:
                    wordPronunciationSection
                case .sentencePronunciation:
                    sentencePronunciationSection
                }
            }
            .padding()
            .background(
                ScrollViewScrollerConfigurator(
                    hidesVerticalScroller: hidesScrollIndicator
                )
            )
        }
        .scrollIndicators(hidesScrollIndicator ? .hidden : .automatic, axes: .vertical)
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

            ReorderableVStack(items: $sources, content: { source, index in
                IntegratedDictionaryRow(
                    source: source,
                    downloadState: downloadState(for: source.wrappedValue.type),
                    onToggle: { updateSources() },
                    onDownloadComplete: { handleDownloadComplete(for: source.wrappedValue.type) },
                    onDelete: {
                        performDelete(for: source.wrappedValue.type)
                        handleDelete(for: source.wrappedValue.type)
                    },
                    onDownload: { performDownload(for: source.wrappedValue.type) },
                    onCancel: { performCancel(for: source.wrappedValue.type) },
                    onRetry: { performRetry(for: source.wrappedValue.type) }
                )
            }, onMove: moveSource)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var wordPronunciationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Word Pronunciation Service"))
                    .font(.headline)
                Text(L("Select TTS service for word pronunciation. Apple is offline, others require network."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)
            .padding(.top)

            VStack(spacing: 6) {
                ForEach(TTSProvider.allCases) { provider in
                    TTSServiceRow(
                        provider: provider,
                        isSelected: model.settings.wordTTSProvider == provider,
                        latency: ttsTester.latencies[provider] ?? .pending,
                        onSelect: { model.settings.wordTTSProvider = provider }
                    )
                }
            }
            .padding(.horizontal)

            englishAccentSection(for: model.settings.wordTTSProvider)

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

    private var sentencePronunciationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sentence Pronunciation Service"))
                    .font(.headline)
                Text(L("Select TTS service for sentence pronunciation. Apple is offline, others require network."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)
            .padding(.top)

            VStack(spacing: 6) {
                ForEach(TTSProvider.allCases) { provider in
                    TTSServiceRow(
                        provider: provider,
                        isSelected: model.settings.sentenceTTSProvider == provider,
                        latency: ttsTester.latencies[provider] ?? .pending,
                        onSelect: { model.settings.sentenceTTSProvider = provider }
                    )
                }
            }
            .padding(.horizontal)

            englishAccentSection(for: model.settings.sentenceTTSProvider)

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

    @ViewBuilder
    private func englishAccentSection(for provider: TTSProvider) -> some View {
        if provider != .apple && provider != .google {
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
    }

    private var sentenceTranslationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sentence Translation"))
                    .font(.headline)
                Text(L("Drag to reorder service priority. Enabled services will be shown in the paragraph translation panel."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            ReorderableVStack(items: $sentenceSources, content: { source, index in
                SentenceServiceRow(
                    source: source,
                    latency: sentenceLatencyTester.latencies[source.wrappedValue.type] ?? .pending,
                    onToggle: { updateSentenceSources() }
                )
            }, onMove: moveSentenceSource)
            .padding(.horizontal)

            HStack {
                Spacer()
                Button {
                    Task { await sentenceLatencyTester.testAll() }
                } label: {
                    HStack(spacing: 6) {
                        if sentenceLatencyTester.isTesting {
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
                .disabled(sentenceLatencyTester.isTesting)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var learningSection: some View {
        LearningSettingsView(modelContext: model.modelContext)
    }

    // MARK: - Private Helpers

    private func downloadState(for type: DictionarySource.SourceType) -> DownloadState? {
        switch type {
        case .ecdict:
            return convertState(model.dictionaryDownload.state)
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

    private func performDownload(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.startDownload()
        case .system:
            break
        }
    }

    private func performCancel(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.cancelDownload()
        case .system:
            break
        }
    }

    private func performDelete(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.delete()
        case .system:
            break
        }
    }

    private func performRetry(for type: DictionarySource.SourceType) {
        switch type {
        case .ecdict:
            model.dictionaryDownload.retry()
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

    private func loadSentenceSources() {
        sentenceSources = model.settings.sentenceTranslationSources
    }

    private func updateSources() {
        model.settings.dictionarySources = sources
    }

    private func updateSentenceSources() {
        model.settings.sentenceTranslationSources = sentenceSources
    }

    private func moveSource(from indices: IndexSet, to offset: Int) {
        sources.move(fromOffsets: indices, toOffset: offset)
        updateSources()
    }

    private func moveSentenceSource(from indices: IndexSet, to offset: Int) {
        sentenceSources.move(fromOffsets: indices, toOffset: offset)
        updateSentenceSources()
    }
}

// MARK: - Reorderable VStack

struct ReorderableVStack<Content: View, Item: Identifiable & Equatable>: View {
    @Binding var items: [Item]
    @ViewBuilder let content: (Binding<Item>, Int) -> Content
    let onMove: (IndexSet, Int) -> Void
    @State private var draggingItem: Item?
    @State private var draggedIndex: Int?
    @State private var targetIndex: Int?
    @State private var itemFrames: [Int: CGRect] = [:]
    @State private var dragPosition: CGPoint?

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                ForEach(Array($items.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .top) {
                        content(item, index)
                            .opacity(draggedIndex == index ? 0.3 : 1)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(key: ItemFrameKey.self, value: [index: geo.frame(in: .named("reorderableContainer"))])
                                }
                            )

                        // Insertion indicator above current item
                        if let target = targetIndex, target == index, draggedIndex != index {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .shadow(color: Color.accentColor.opacity(0.5), radius: 2)
                                .offset(y: -5)
                        }

                        // Insertion indicator at the end (after last item)
                        if index == items.count - 1,
                           let target = targetIndex,
                           target == items.count,
                           draggedIndex != items.count - 1 {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .shadow(color: Color.accentColor.opacity(0.5), radius: 2)
                                .offset(y: geoHeight(for: index) - 3)
                        }
                    }
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("reorderableContainer"))
                            .onChanged { value in
                                if draggedIndex == nil {
                                    draggedIndex = index
                                    draggingItem = items[index]
                                    // Initialize drag position to item's center
                                    if let frame = itemFrames[index] {
                                        dragPosition = CGPoint(x: frame.midX, y: frame.midY)
                                    }
                                }

                                // Update drag position to follow mouse
                                dragPosition = value.location

                                // Calculate target index based on actual frame positions
                                let target = calculateTargetIndex(at: value.location)
                                if target != targetIndex {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        targetIndex = target
                                    }
                                }
                            }
                            .onEnded { _ in
                                if let from = draggedIndex, let to = targetIndex {
                                    let actualTo = to > from ? to : to
                                    if from != actualTo && from != actualTo - 1 {
                                        withAnimation(.spring(duration: 0.3)) {
                                            onMove(IndexSet([from]), actualTo)
                                        }
                                    }
                                }
                                draggingItem = nil
                                draggedIndex = nil
                                targetIndex = nil
                                dragPosition = nil
                            }
                    )
                }
            }
            .coordinateSpace(name: "reorderableContainer")
            .onPreferenceChange(ItemFrameKey.self) { frames in
                itemFrames = frames
            }

            // Floating dragged item that follows mouse
            if let draggedIndex = draggedIndex,
               let item = draggingItem,
               let position = dragPosition,
               let frame = itemFrames[draggedIndex] {
                content(Binding(
                    get: { item },
                    set: { _ in }
                ), draggedIndex)
                .frame(width: frame.width, height: frame.height)
                .position(x: position.x, y: position.y)
                .scaleEffect(1.03)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                )
                .opacity(0.95)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.05), value: position)
            }
        }
    }

    private func geoHeight(for index: Int) -> CGFloat {
        itemFrames[index]?.height ?? 76
    }

    private func calculateTargetIndex(at point: CGPoint) -> Int {
        guard !itemFrames.isEmpty else { return 0 }

        let sortedFrames = itemFrames.sorted { $0.key < $1.key }

        // Handle before first item
        if let first = sortedFrames.first, point.y < first.value.midY {
            return first.key
        }

        // Handle between items
        for (i, frame) in sortedFrames {
            guard let next = sortedFrames.first(where: { $0.key > i }) else { continue }
            let midY = (frame.midY + next.value.midY) / 2
            if point.y >= frame.midY && point.y < midY {
                return next.key
            }
        }

        // Handle after last item
        if let last = sortedFrames.last {
            return last.key + 1
        }

        return 0
    }
}

struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ScrollViewScrollerConfigurator: NSViewRepresentable {
    let hidesVerticalScroller: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView ?? nsView.firstSuperview(of: NSScrollView.self) else {
                return
            }

            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = !hidesVerticalScroller
            scrollView.verticalScroller?.isHidden = hidesVerticalScroller
            scrollView.verticalScroller?.alphaValue = hidesVerticalScroller ? 0 : 1
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

extension NSView {
    func firstSuperview<T: NSView>(of type: T.Type) -> T? {
        var candidate = superview
        while let view = candidate {
            if let match = view as? T {
                return match
            }
            candidate = view.superview
        }
        return nil
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
                        .frame(width: 32, alignment: .leading)
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
        source.type.needsDownloadManagement
    }

    private var isInstalled: Bool {
        guard let state = downloadState else { return true }
        if case .installed = state { return true }
        return false
    }

}
