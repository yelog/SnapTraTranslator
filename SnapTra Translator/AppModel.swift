import AppKit
import Combine
import Foundation
import SwiftUI
import Translation
import UserNotifications

struct OverlayContent: Equatable {
    var word: String
    var phonetic: String?
    var primaryTranslationState: OverlayPrimaryTranslationState
    var dictionarySections: [OverlayDictionarySection]

    init(
        word: String,
        phonetic: String?,
        primaryTranslationState: OverlayPrimaryTranslationState,
        dictionarySections: [OverlayDictionarySection] = []
    ) {
        self.word = word
        self.phonetic = phonetic
        self.primaryTranslationState = primaryTranslationState
        self.dictionarySections = dictionarySections
    }

    var translation: String {
        if case .ready(let text, _) = primaryTranslationState {
            return text
        }
        return word
    }

    var dictionaryEntries: [DictionaryEntry] {
        dictionarySections.compactMap(\.entry)
    }

    var hasReadyDictionaryEntries: Bool {
        !dictionaryEntries.isEmpty
    }

    /// Backward compatibility: returns definitions from first dictionary entry
    var definitions: [DictionaryEntry.Definition] {
        dictionaryEntries.first?.definitions ?? []
    }

    /// Backward compatibility: returns source from first dictionary entry
    var dictionarySource: DictionaryEntry.Source? {
        dictionaryEntries.first?.source
    }
}

enum OverlayPrimaryTranslationState: Equatable {
    case loading
    case ready(String, isFallback: Bool)
    case empty
    case failed(String)
}

struct OverlayDictionarySection: Equatable, Identifiable {
    let sourceType: DictionarySource.SourceType
    var state: OverlayDictionarySectionState

    var id: String {
        sourceType.rawValue
    }

    var entry: DictionaryEntry? {
        guard case .ready(let entry) = state else { return nil }
        return entry
    }
}

enum OverlayDictionarySectionState: Equatable {
    case loading
    case ready(DictionaryEntry)
    case empty
    case failed(String)
}

enum OverlayState: Equatable {
    case idle
    case loading(String?)
    case result(OverlayContent)
    case error(String)
    case noWord
}

private enum CachedLanguageAvailabilityStatus: String {
    case installed
    case supported
    case unsupported

    @available(macOS 15.0, *)
    init(_ status: LanguageAvailability.Status) {
        switch status {
        case .installed:
            self = .installed
        case .supported:
            self = .supported
        case .unsupported:
            self = .unsupported
        @unknown default:
            self = .unsupported
        }
    }

    @available(macOS 15.0, *)
    var translationStatus: LanguageAvailability.Status {
        switch self {
        case .installed:
            return .installed
        case .supported:
            return .supported
        case .unsupported:
            return .unsupported
        }
    }
}

private struct DictionarySectionResult {
    let sourceType: DictionarySource.SourceType
    let state: OverlayDictionarySectionState
    let phonetic: String?
    let fallbackTranslation: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var overlayState: OverlayState = .idle
    @Published var overlayAnchor: CGPoint = .zero

    @Published var settings: SettingsStore
    let permissions: PermissionManager
    let translationBridge: TranslationBridge
    private var _languagePackManager: Any?

    @available(macOS 15.0, *)
    var languagePackManager: LanguagePackManager? {
        get { _languagePackManager as? LanguagePackManager }
        set { _languagePackManager = newValue }
    }

    private let hotkeyManager = HotkeyManager()
    private let captureService = ScreenCaptureService()
    private let ocrService = OCRService()
    private let dictionaryService = DictionaryService()
    private let speechService = SpeechService()
    let dictionaryDownload: DictionaryDownloadManager
    let wordNetDownload: WordNetDownloadManager
    private var cancellables = Set<AnyCancellable>()
    private var lookupTask: Task<Void, Never>?
    private var activeLookupID: UUID?
    private var isHotkeyActive = false
    private var lastAvailabilityKey: String?
    private var cachedLanguageStatuses: [String: CachedLanguageAvailabilityStatus] = [:]

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastOcrPosition: CGPoint?
    private let debounceInterval: TimeInterval = 0.1
    private let positionThreshold: CGFloat = 10.0

    private let debugOverlayWindowController = DebugOverlayWindowController()
    lazy var overlayWindowController = OverlayWindowController(model: self)

    @MainActor
    init(settings: SettingsStore? = nil, permissions: PermissionManager? = nil) {
        let resolvedSettings = settings ?? SettingsStore()
        let resolvedPermissions = permissions ?? PermissionManager()
        self.settings = resolvedSettings
        self.permissions = resolvedPermissions
        self.translationBridge = TranslationBridge()
        self.dictionaryDownload = DictionaryDownloadManager(offlineService: dictionaryService.offlineService)
        self.wordNetDownload = WordNetDownloadManager(wordNetService: dictionaryService.wordNetService)

        // Forward SettingsStore changes to AppModel so SwiftUI redraws
        resolvedSettings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward DictionaryDownloadManager changes to AppModel so SwiftUI redraws
        self.dictionaryDownload.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward WordNetDownloadManager changes to AppModel so SwiftUI redraws
        self.wordNetDownload.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        if #available(macOS 15.0, *) {
            let manager = LanguagePackManager()
            self.languagePackManager = manager
            // Forward LanguagePackManager changes to AppModel so SwiftUI redraws
            manager.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
        bindSettings()
        resolvedPermissions.$status
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        hotkeyManager.onTrigger = { [weak self] in
            self?.handleHotkeyTrigger()
        }
        hotkeyManager.onRelease = { [weak self] in
            self?.handleHotkeyRelease()
        }
        resolvedPermissions.refreshStatus()
        Task {
            await checkLanguageAvailability()
        }
    }

    func handleHotkeyTrigger() {
        isHotkeyActive = true
        lastOcrPosition = NSEvent.mouseLocation
        overlayWindowController.setInteractive(false)
        startMouseTracking()
        startLookup()
    }

    func handleHotkeyRelease() {
        isHotkeyActive = false
        stopMouseTracking()
        debugOverlayWindowController.hide()

        // 松开快捷键时隐藏气泡
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        overlayState = .idle
        overlayWindowController.setInteractive(false)
        overlayWindowController.hide()
    }

    /// 手动关闭气泡（用于非持续翻译模式）
    func dismissOverlay() {
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        overlayState = .idle
        overlayWindowController.setInteractive(false)
        overlayWindowController.hide()
    }
    
    private func startMouseTracking() {
        guard globalMouseMonitor == nil else { return }
        
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
        }
        
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved()
            }
            return event
        }
    }
    
    private func stopMouseTracking() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lastOcrPosition = nil
    }
    
    private func handleMouseMoved() {
        guard isHotkeyActive else { return }

        // 如果关闭了持续翻译，鼠标移动不触发翻译
        guard settings.continuousTranslation else { return }

        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isHotkeyActive else { return }

                let currentPosition = NSEvent.mouseLocation

                if let lastPosition = self.lastOcrPosition {
                    let dx = abs(currentPosition.x - lastPosition.x)
                    let dy = abs(currentPosition.y - lastPosition.y)
                    if dx < self.positionThreshold && dy < self.positionThreshold {
                        return
                    }
                }

                self.lastOcrPosition = currentPosition
                self.overlayAnchor = currentPosition
                if case .idle = self.overlayState {
                    self.startLookup()
                } else {
                    self.overlayWindowController.show(at: currentPosition)
                    self.startLookup()
                }
            }
        }
        debounceWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func startLookup() {
        lookupTask?.cancel()
        let lookupID = UUID()
        activeLookupID = lookupID
        lookupTask = Task { [weak self] in
            await self?.performLookup(lookupID: lookupID)
        }
    }

    func performLookup(lookupID: UUID) async {
        guard !Task.isCancelled, activeLookupID == lookupID else { return }
        guard permissions.status.screenRecording else {
            updateOverlay(state: .error(L("Enable Screen Recording")), anchor: NSEvent.mouseLocation)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        guard activeLookupID == lookupID else { return }

        // 只在调试模式下显示初始 loading 状态
        if settings.debugShowOcrRegion {
            updateOverlay(state: .loading(nil), anchor: mouseLocation)
        }

        guard let capture = await captureService.captureAroundCursor() else {
            debugOverlayWindowController.hide()
            if settings.debugShowOcrRegion {
                updateOverlay(state: .error(L("Capture failed")), anchor: mouseLocation)
            }
            return
        }
        if settings.debugShowOcrRegion {
            debugOverlayWindowController.show(at: capture.region.rect)
        } else {
            debugOverlayWindowController.hide()
        }
        guard !Task.isCancelled, activeLookupID == lookupID else { return }
        let normalizedPoint = normalizedCursorPoint(mouseLocation, in: capture.region.rect)
        do {
            let words = try await ocrService.recognizeWords(
                in: capture.image,
                language: settings.sourceLanguage
            )
            guard !Task.isCancelled, activeLookupID == lookupID else { return }
            if settings.debugShowOcrRegion {
                let wordBoxes = words.map { $0.boundingBox }
                debugOverlayWindowController.show(at: capture.region.rect, wordBoxes: wordBoxes)
            }
            guard let selected = selectWord(from: words, normalizedPoint: normalizedPoint) else {
                // 只在调试模式下显示 "No word detected" 气泡
                if settings.debugShowOcrRegion {
                    updateOverlay(state: .noWord, anchor: mouseLocation)
                } else {
                    // 非调试模式下，隐藏气泡
                    overlayState = .idle
                    overlayWindowController.hide()
                }
                return
            }
            guard activeLookupID == lookupID else { return }

            let languagePair = resolveLookupLanguagePair()
            let sourceLanguage = languagePair.sourceLanguage
            let targetLanguage = languagePair.targetLanguage

            if settings.playPronunciation {
                let languageCode = sourceLanguage.languageCode?.identifier
                speechService.speak(
                    selected.text,
                    language: languageCode,
                    provider: settings.ttsProvider,
                    useAmericanAccent: settings.englishAccent.isAmerican
                )
            }
            guard !Task.isCancelled, activeLookupID == lookupID else { return }

            let initialContent = makeInitialOverlayContent(
                word: selected.text,
                sources: settings.dictionarySources,
                primaryTranslationState: languagePair.isSameLanguage
                    ? .ready(selected.text, isFallback: false)
                    : .loading
            )
            updateOverlay(state: .result(initialContent), anchor: mouseLocation)

            let enabledSources = settings.dictionarySources.filter(\.isEnabled)
            await withTaskGroup(of: Void.self) { group in
                if !languagePair.isSameLanguage {
                    group.addTask { [weak self, translationBridge] in
                        guard let self else { return }
                        let translationState = await self.loadPrimaryTranslationState(
                            word: selected.text,
                            languagePair: languagePair,
                            sourceLanguage: sourceLanguage,
                            targetLanguage: targetLanguage,
                            translationBridge: translationBridge
                        )
                        await self.applyPrimaryTranslationState(
                            translationState,
                            lookupID: lookupID,
                            anchor: mouseLocation
                        )
                    }
                }

                for source in enabledSources {
                    group.addTask { [weak self, dictionaryService, translationBridge] in
                        guard let self else { return }
                        let result = await Self.lookupDictionarySection(
                            word: selected.text,
                            source: source,
                            dictionaryService: dictionaryService,
                            sourceIdentifier: languagePair.sourceIdentifier,
                            targetIdentifier: languagePair.targetIdentifier,
                            preferEnglish: languagePair.targetIsEnglish,
                            sourceLanguage: sourceLanguage,
                            targetLanguage: targetLanguage,
                            translationBridge: translationBridge
                        )
                        await self.applyDictionarySectionResult(
                            result,
                            lookupID: lookupID,
                            anchor: mouseLocation
                        )
                    }
                }
            }
        } catch is CancellationError {
            // Task was cancelled, do nothing
        } catch {
            updateOverlay(state: .error(L("Translation failed: \(error.localizedDescription)")), anchor: mouseLocation)
        }
    }

    private func makeInitialOverlayContent(
        word: String,
        sources: [DictionarySource],
        primaryTranslationState: OverlayPrimaryTranslationState
    ) -> OverlayContent {
        OverlayContent(
            word: word,
            phonetic: nil,
            primaryTranslationState: primaryTranslationState,
            dictionarySections: sources
                .filter(\.isEnabled)
                .map { OverlayDictionarySection(sourceType: $0.type, state: .loading) }
        )
    }

    private func loadPrimaryTranslationState(
        word: String,
        languagePair: LookupLanguagePair,
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        translationBridge: TranslationBridge
    ) async -> OverlayPrimaryTranslationState {
        if #available(macOS 15.0, *) {
            let status = await languageAvailabilityStatus(for: languagePair)
            guard status == .installed else {
                return .failed(message(for: status))
            }

            do {
                let translated = try await translationBridge.translate(
                    text: word,
                    source: sourceLanguage,
                    target: targetLanguage
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                return translated.isEmpty ? .empty : .ready(translated, isFallback: false)
            } catch TranslationError.timeout {
                return .failed(L("Translation timeout. Please try again."))
            } catch {
                return .failed(L("Translation failed: \(error.localizedDescription)"))
            }
        } else {
            return .failed(L("Translation requires macOS 15"))
        }
    }

    private func applyPrimaryTranslationState(
        _ state: OverlayPrimaryTranslationState,
        lookupID: UUID,
        anchor: CGPoint
    ) {
        updateOverlayContent(for: lookupID, anchor: anchor) { content in
            switch state {
            case .ready:
                content.primaryTranslationState = state
            case .loading:
                content.primaryTranslationState = .loading
            case .empty:
                if case .ready(_, let isFallback) = content.primaryTranslationState, isFallback {
                    break
                }
                content.primaryTranslationState = .empty
            case .failed:
                if case .ready(_, let isFallback) = content.primaryTranslationState, isFallback {
                    break
                }
                content.primaryTranslationState = state
            }
        }
    }

    private func applyDictionarySectionResult(
        _ result: DictionarySectionResult,
        lookupID: UUID,
        anchor: CGPoint
    ) {
        updateOverlayContent(for: lookupID, anchor: anchor) { content in
            guard let index = content.dictionarySections.firstIndex(where: { $0.sourceType == result.sourceType }) else {
                return
            }

            content.dictionarySections[index].state = result.state

            if let phonetic = result.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
               !phonetic.isEmpty,
               (content.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                content.phonetic = phonetic
            }

            guard case .ready(_, let isFallback) = content.primaryTranslationState else {
                if case .loading = content.primaryTranslationState {
                    updateFallbackPrimaryTranslation(for: &content)
                } else if case .empty = content.primaryTranslationState {
                    updateFallbackPrimaryTranslation(for: &content)
                } else if case .failed = content.primaryTranslationState {
                    updateFallbackPrimaryTranslation(for: &content)
                }
                return
            }

            if isFallback {
                updateFallbackPrimaryTranslation(for: &content)
            }
        }
    }

    private func updateOverlayContent(
        for lookupID: UUID,
        anchor: CGPoint,
        mutate: (inout OverlayContent) -> Void
    ) {
        guard activeLookupID == lookupID,
              case .result(var content) = overlayState else {
            return
        }

        mutate(&content)
        updateOverlay(state: .result(content), anchor: anchor)
    }

    private func updateFallbackPrimaryTranslation(for content: inout OverlayContent) {
        guard let fallback = content.dictionarySections.lazy.compactMap(\.entry).compactMap(\.primaryTranslation).first else {
            return
        }
        content.primaryTranslationState = .ready(fallback, isFallback: true)
    }

    func updateOverlay(state: OverlayState, anchor: CGPoint? = nil) {
        guard isHotkeyActive || !settings.continuousTranslation else { return }
        
        if let anchor {
            overlayAnchor = anchor
        }
        switch state {
        case .error(let message):
            sendNotification(title: "SnapTra Translator", body: message)
        case .idle:
            break
        case .result:
            overlayState = state
            overlayWindowController.show(at: overlayAnchor)
            if !settings.continuousTranslation {
                overlayWindowController.setInteractive(true)
            }
        default:
            overlayState = state
            overlayWindowController.show(at: overlayAnchor)
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func bindSettings() {
        settings.$singleKey
            .sink { [weak self] singleKey in
                self?.hotkeyManager.start(singleKey: singleKey)
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .sink { value in
                LoginItemManager.setEnabled(value)
            }
            .store(in: &cancellables)

        settings.$debugShowOcrRegion
            .sink { [weak self] isEnabled in
                if !isEnabled {
                    self?.debugOverlayWindowController.hide()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settings.$sourceLanguage,
            settings.$targetLanguage
        )
        .sink { [weak self] _, _ in
            self?.handleTranslationSettingsChanged()
        }
        .store(in: &cancellables)

        permissions.$status
            .sink { [weak self] status in
                if status.screenRecording {
                    self?.restartHotkey()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.restartHotkey()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.handleScreenConfigurationChange()
            }
            .store(in: &cancellables)
    }

    private func handleScreenConfigurationChange() {
        captureService.invalidateCache()
        guard isHotkeyActive else { return }
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        overlayState = .idle
        overlayWindowController.hide()
        debugOverlayWindowController.hide()
    }

    private func restartHotkey() {
        guard !isHotkeyActive else { return }
        hotkeyManager.start(singleKey: settings.singleKey)
    }

    private func handleTranslationSettingsChanged() {
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        lastAvailabilityKey = nil
        cachedLanguageStatuses.removeAll()
        translationBridge.cancelAllPendingRequests()

        if overlayState != .idle {
            overlayState = .idle
            overlayWindowController.hide()
        }

        Task {
            await checkLanguageAvailability()
        }
    }

    private func checkLanguageAvailability() async {
        guard #available(macOS 15.0, *) else { return }
        let pairs = requiredLanguagePairsForCurrentSettings()
        var statusesByKey: [String: CachedLanguageAvailabilityStatus] = [:]

        for pair in pairs {
            statusesByKey[pair.key] = await languageAvailabilityStatus(for: pair, useCache: false)
        }

        let key = pairs
            .map { pair in
                let status = statusesByKey[pair.key] ?? .unsupported
                return "\(pair.key)=\(status.rawValue)"
            }
            .joined(separator: "|")

        guard key != lastAvailabilityKey else { return }
        lastAvailabilityKey = key

        guard let firstUnavailable = pairs.lazy.compactMap({ pair in
            let status = statusesByKey[pair.key] ?? .unsupported
            return status == .installed ? nil : status
        }).first else {
            return
        }

        sendNotification(
            title: L("SnapTra Translator"),
            body: message(for: firstUnavailable)
        )
    }

    private func resolveLookupLanguagePair() -> LookupLanguagePair {
        .fixed(
            sourceIdentifier: settings.sourceLanguage,
            targetIdentifier: settings.targetLanguage
        )
    }

    private func requiredLanguagePairsForCurrentSettings() -> [LookupLanguagePair] {
        [
            .fixed(
                sourceIdentifier: settings.sourceLanguage,
                targetIdentifier: settings.targetLanguage
            )
        ]
    }

    private func languageAvailabilityStatus(
        for pair: LookupLanguagePair,
        useCache: Bool = true
    ) async -> CachedLanguageAvailabilityStatus {
        if pair.isSameLanguage {
            cachedLanguageStatuses[pair.key] = .installed
            return .installed
        }

        if useCache, let cached = cachedLanguageStatuses[pair.key] {
            return cached
        }

        let status: CachedLanguageAvailabilityStatus
        if #available(macOS 15.0, *) {
            let availability = LanguageAvailability()
            let systemStatus = await availability.status(from: pair.sourceLanguage, to: pair.targetLanguage)
            status = CachedLanguageAvailabilityStatus(systemStatus)
        } else {
            status = .unsupported
        }

        cachedLanguageStatuses[pair.key] = status
        return status
    }

    private func message(for status: CachedLanguageAvailabilityStatus) -> String {
        switch status {
        case .installed:
            return ""
        case .supported:
            return L("Language pack required. Please download in System Settings > General > Language & Region > Translation.")
        case .unsupported:
            return L("Translation not supported for this language pair.")
        }
    }

    private func normalizedCursorPoint(_ mouseLocation: CGPoint, in rect: CGRect) -> CGPoint {
        let x = (mouseLocation.x - rect.minX) / rect.width
        let y = (mouseLocation.y - rect.minY) / rect.height
        return CGPoint(x: x, y: y)
    }

    private static func lookupDictionarySection(
        word: String,
        source: DictionarySource,
        dictionaryService: DictionaryService,
        sourceIdentifier: String,
        targetIdentifier: String,
        preferEnglish: Bool,
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        translationBridge: TranslationBridge
    ) async -> DictionarySectionResult {
        guard let entry = await dictionaryService.lookupSingle(
            word,
            source: source,
            sourceLanguage: sourceIdentifier,
            targetLanguage: targetIdentifier,
            preferEnglish: preferEnglish
        ) else {
            return DictionarySectionResult(
                sourceType: source.type,
                state: .empty,
                phonetic: nil,
                fallbackTranslation: nil
            )
        }

        let processedEntry: DictionaryEntry?
        if sourceLanguage.minimalIdentifier == targetLanguage.minimalIdentifier {
            processedEntry = processSameLanguageEntry(entry, isEnglish: sourceLanguage.minimalIdentifier == "en")
        } else if entry.isPretranslated {
            processedEntry = entry
        } else {
            let translatedDefinitions = await translateDefinitionsInParallel(
                definitions: entry.definitions,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                translationBridge: translationBridge
            )

            if translatedDefinitions.isEmpty {
                processedEntry = nil
            } else {
                processedEntry = DictionaryEntry(
                    word: entry.word,
                    phonetic: entry.phonetic,
                    definitions: translatedDefinitions,
                    source: entry.source,
                    synonyms: entry.synonyms,
                    isPretranslated: entry.isPretranslated
                )
            }
        }

        guard let processedEntry else {
            return DictionarySectionResult(
                sourceType: source.type,
                state: .empty,
                phonetic: entry.phonetic,
                fallbackTranslation: nil
            )
        }

        return DictionarySectionResult(
            sourceType: source.type,
            state: .ready(processedEntry),
            phonetic: processedEntry.phonetic,
            fallbackTranslation: processedEntry.primaryTranslation
        )
    }

    private static func processSameLanguageEntry(
        _ entry: DictionaryEntry,
        isEnglish: Bool
    ) -> DictionaryEntry? {
        var processedDefinitions = entry.definitions

        if isEnglish && !entry.definitions.isEmpty {
            processedDefinitions = entry.definitions.compactMap { def in
                let trimmedMeaning = def.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasEnglishContent = trimmedMeaning.range(of: "[a-zA-Z]{3,}", options: .regularExpression) != nil
                guard hasEnglishContent else { return nil }
                return DictionaryEntry.Definition(
                    partOfSpeech: def.partOfSpeech,
                    field: def.field,
                    meaning: def.meaning,
                    translation: trimmedMeaning,
                    examples: def.examples
                )
            }
        }

        guard !processedDefinitions.isEmpty else { return nil }
        return DictionaryEntry(
            word: entry.word,
            phonetic: entry.phonetic,
            definitions: processedDefinitions,
            source: entry.source,
            synonyms: entry.synonyms,
            isPretranslated: entry.isPretranslated
        )
    }

    private static func translateDefinitionsInParallel(
        definitions: [DictionaryEntry.Definition],
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        translationBridge: TranslationBridge
    ) async -> [DictionaryEntry.Definition] {
        let targetIsChinese = targetLanguage.minimalIdentifier == "zh"
        let targetIsEnglish = targetLanguage.minimalIdentifier == "en"
        let isSameLanguage = sourceLanguage.minimalIdentifier == targetLanguage.minimalIdentifier

        return await withTaskGroup(of: (Int, DictionaryEntry.Definition?).self) { group in
            for (index, def) in definitions.enumerated() {
                group.addTask { [translationBridge] in
                    let trimmedTranslation = def.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let hasDictionaryTranslation = !trimmedTranslation.isEmpty
                    let shouldKeepDictionaryTranslation = targetIsChinese && hasDictionaryTranslation

                    if shouldKeepDictionaryTranslation {
                        return (index, def)
                    }

                    if targetIsEnglish {
                        let trimmedMeaning = def.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                        let hasEnglishContent = trimmedMeaning.range(of: "[a-zA-Z]{3,}", options: .regularExpression) != nil
                        if hasEnglishContent {
                            return (index, DictionaryEntry.Definition(
                                partOfSpeech: def.partOfSpeech,
                                field: def.field,
                                meaning: def.meaning,
                                translation: trimmedMeaning,
                                examples: def.examples
                            ))
                        }
                        return (index, nil)
                    }

                    let translatedText: String
                    if isSameLanguage {
                        translatedText = def.meaning
                    } else if let meaningTranslation = try? await translationBridge.translate(
                        text: def.meaning,
                        source: sourceLanguage,
                        target: targetLanguage
                    ) {
                        translatedText = meaningTranslation
                    } else if hasDictionaryTranslation {
                        translatedText = trimmedTranslation
                    } else if targetIsEnglish {
                        translatedText = def.meaning
                    } else {
                        return (index, nil)
                    }

                    return (index, DictionaryEntry.Definition(
                        partOfSpeech: def.partOfSpeech,
                        field: def.field,
                        meaning: def.meaning,
                        translation: translatedText,
                        examples: def.examples
                    ))
                }
            }

            var results: [(Int, DictionaryEntry.Definition)] = []
            for await (index, def) in group {
                if let def {
                    results.append((index, def))
                }
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private func selectWord(from words: [RecognizedWord], normalizedPoint: CGPoint) -> RecognizedWord? {
        let tolerance: CGFloat = 0.01

        // 筛选边界框包含光标的所有候选单词
        let candidates = words.filter { word in
            let expandedBox = word.boundingBox.insetBy(dx: -tolerance, dy: -tolerance)
            return expandedBox.contains(normalizedPoint)
        }

        guard !candidates.isEmpty else { return nil }

        // 选择边界框中心距离光标最近的单词
        return candidates.min { word1, word2 in
            let dist1 = hypot(word1.boundingBox.midX - normalizedPoint.x,
                              word1.boundingBox.midY - normalizedPoint.y)
            let dist2 = hypot(word2.boundingBox.midX - normalizedPoint.x,
                              word2.boundingBox.midY - normalizedPoint.y)
            return dist1 < dist2
        }
    }
}
