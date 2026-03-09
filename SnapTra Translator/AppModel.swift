import AppKit
import Combine
import Foundation
import SwiftUI
import Translation
import UserNotifications

struct OverlayContent: Equatable {
    var word: String
    var phonetic: String?
    var translation: String
    var dictionaryEntries: [DictionaryEntry]  // Multiple dictionary results

    init(
        word: String,
        phonetic: String?,
        translation: String,
        dictionaryEntries: [DictionaryEntry] = []
    ) {
        self.word = word
        self.phonetic = phonetic
        self.translation = translation
        self.dictionaryEntries = dictionaryEntries
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

        var fallbackContent: OverlayContent?
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
                preferredLanguages: ocrRecognitionLanguages
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

            updateOverlay(state: .loading(selected.text), anchor: mouseLocation)
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

            let dictEntries = await dictionaryService.lookupAll(
                selected.text,
                sources: settings.dictionarySources,
                sourceLanguage: languagePair.sourceIdentifier,
                targetLanguage: languagePair.targetIdentifier,
                preferEnglish: languagePair.targetIsEnglish
            )
            let phonetic = dictEntries.first?.phonetic
            fallbackContent = makeFallbackOverlayContent(
                word: selected.text,
                phonetic: phonetic,
                entries: dictEntries
            )

            if languagePair.isSameLanguage {
                // Same language: process definitions from all dictionaries
                var allProcessedEntries: [DictionaryEntry] = []
                let isEnglish = sourceLanguage.minimalIdentifier == "en"

                for entry in dictEntries {
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

                    if !processedDefinitions.isEmpty {
                        allProcessedEntries.append(DictionaryEntry(
                            word: entry.word,
                            phonetic: entry.phonetic,
                            definitions: processedDefinitions,
                            source: entry.source,
                            synonyms: entry.synonyms
                        ))
                    }
                }

                let content = OverlayContent(
                    word: selected.text,
                    phonetic: phonetic,
                    translation: selected.text,
                    dictionaryEntries: allProcessedEntries
                )
                updateOverlay(state: .result(content), anchor: mouseLocation)
                return
            }

            if #available(macOS 15.0, *) {
                let status = await languageAvailabilityStatus(for: languagePair)
                guard status == .installed else {
                    if let fallbackContent {
                        updateOverlay(state: .result(fallbackContent), anchor: mouseLocation)
                    } else {
                        updateOverlay(state: .error(message(for: status)), anchor: mouseLocation)
                    }
                    return
                }

                let translated = try await translationBridge.translate(text: selected.text, source: sourceLanguage, target: targetLanguage)
                guard !Task.isCancelled, activeLookupID == lookupID else { return }

                // Translate definitions from all dictionaries
                var translatedEntries: [DictionaryEntry] = []
                for entry in dictEntries {
                    if entry.isPretranslated {
                        translatedEntries.append(entry)
                        continue
                    }

                    let translatedDefinitions = await translateDefinitionsInParallel(
                        definitions: entry.definitions,
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage
                    )
                    if !translatedDefinitions.isEmpty {
                        translatedEntries.append(DictionaryEntry(
                            word: entry.word,
                            phonetic: entry.phonetic,
                            definitions: translatedDefinitions,
                            source: entry.source,
                            synonyms: entry.synonyms,
                            isPretranslated: entry.isPretranslated
                        ))
                    }
                }

                let content = OverlayContent(
                    word: selected.text,
                    phonetic: phonetic,
                    translation: translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? (fallbackContent?.translation ?? selected.text)
                        : translated,
                    dictionaryEntries: translatedEntries
                )
                updateOverlay(state: .result(content), anchor: mouseLocation)
            } else {
                if let fallbackContent {
                    updateOverlay(state: .result(fallbackContent), anchor: mouseLocation)
                } else {
                    updateOverlay(state: .error(L("Translation requires macOS 15")), anchor: mouseLocation)
                }
            }
        } catch is CancellationError {
            // Task was cancelled, do nothing
        } catch TranslationError.timeout {
            if let fallbackContent {
                updateOverlay(state: .result(fallbackContent), anchor: mouseLocation)
            } else {
                updateOverlay(state: .error(L("Translation timeout. Please try again.")), anchor: mouseLocation)
            }
        } catch {
            if let fallbackContent {
                updateOverlay(state: .result(fallbackContent), anchor: mouseLocation)
            } else {
                updateOverlay(state: .error(L("Translation failed: \(error.localizedDescription)")), anchor: mouseLocation)
            }
        }
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

    private var ocrRecognitionLanguages: [String] {
        var seen = Set<String>()
        return [settings.sourceLanguage, settings.targetLanguage].filter { seen.insert($0).inserted }
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

    private func translateDefinitionsInParallel(
        definitions: [DictionaryEntry.Definition],
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language
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
                    } else {
                        translatedText = def.meaning
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

    private func makeFallbackOverlayContent(
        word: String,
        phonetic: String?,
        entries: [DictionaryEntry]
    ) -> OverlayContent? {
        let displayableEntries = entries.filter { entry in
            entry.definitions.contains { definition in
                let translation = definition.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !translation.isEmpty
            }
        }

        guard let translation = displayableEntries.lazy.compactMap(\.primaryTranslation).first else {
            return nil
        }

        return OverlayContent(
            word: word,
            phonetic: phonetic,
            translation: translation,
            dictionaryEntries: displayableEntries
        )
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
