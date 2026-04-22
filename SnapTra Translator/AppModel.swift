import AppKit
import Combine
import Foundation
import SwiftUI
import SwiftData
import Translation
import UserNotifications

struct OverlayContent: Equatable {
    var word: String
    var phonetic: String?
    var primaryTranslationState: OverlayPrimaryTranslationState
    var usesCompactPrimaryTranslationStyle: Bool
    var dictionarySections: [OverlayDictionarySection]

    init(
        word: String,
        phonetic: String?,
        primaryTranslationState: OverlayPrimaryTranslationState,
        usesCompactPrimaryTranslationStyle: Bool,
        dictionarySections: [OverlayDictionarySection] = []
    ) {
        self.word = word
        self.phonetic = phonetic
        self.primaryTranslationState = primaryTranslationState
        self.usesCompactPrimaryTranslationStyle = usesCompactPrimaryTranslationStyle
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

struct ParagraphOverlayContent: Equatable {
    var originalText: String?
    var translationState: ParagraphOverlayTranslationState
    var serviceResults: [ServiceTranslationResult]
    var bodyFontSize: CGFloat
    var useFixedFontSize: Bool

    init(
        originalText: String? = nil,
        translationState: ParagraphOverlayTranslationState,
        serviceResults: [ServiceTranslationResult] = [],
        bodyFontSize: CGFloat = 13,
        useFixedFontSize: Bool = false
    ) {
        self.originalText = originalText
        self.translationState = translationState
        self.serviceResults = serviceResults
        self.bodyFontSize = bodyFontSize
        self.useFixedFontSize = useFixedFontSize
    }
}

enum ParagraphOverlayTranslationState: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

struct ServiceTranslationResult: Equatable, Identifiable {
    let sourceType: SentenceTranslationSource.SourceType
    var state: TranslationResultState

    var id: String { sourceType.rawValue }

    static func == (lhs: ServiceTranslationResult, rhs: ServiceTranslationResult) -> Bool {
        lhs.sourceType == rhs.sourceType && lhs.state == rhs.state
    }
}

enum TranslationResultState: Equatable {
    case loading
    case ready(String)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum OverlayState: Equatable {
    case idle
    case loading(String?)
    case result(OverlayContent)
    case paragraphLoading
    case paragraphResult(ParagraphOverlayContent)
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

private enum ActiveLookupMode {
    case word
    case ocrSentence
    case selectedTextSentence
}

@MainActor
final class AppModel: ObservableObject {
    @Published var overlayState: OverlayState = .idle
    var overlayAnchor: CGPoint = .zero
    var activeParagraphRect: CGRect? = nil
    @Published var overlayPreferredWidth: CGFloat? = nil
    @Published var isParagraphOverlayPinned: Bool = false

    @Published var settings: SettingsStore
    let permissions: PermissionManager
    let translationBridge: TranslationBridge
    var modelContext: ModelContext
    lazy var learningService = LearningService(modelContext: modelContext)
    private var _languagePackManager: Any?

    @available(macOS 15.0, *)
    var languagePackManager: LanguagePackManager? {
        get { _languagePackManager as? LanguagePackManager }
        set { _languagePackManager = newValue }
    }

    private let hotkeyManager = HotkeyManager()
    private let captureService = ScreenCaptureService()
    private let ocrService = OCRService()
    private let selectedTextService = SelectedTextService()
    private let dictionaryService = DictionaryService()
    private let speechService = SpeechService()
    private let sentenceTranslationService = SentenceTranslationService()
    let dictionaryDownload: DictionaryDownloadManager
    private var cancellables = Set<AnyCancellable>()
    private var lookupTask: Task<Void, Never>?
    private var activeLookupID: UUID?
    private var isHotkeyActive = false
    private var activeLookupMode: ActiveLookupMode = .word
    private var lastAvailabilityKey: String?
    private var cachedLanguageStatuses: [String: CachedLanguageAvailabilityStatus] = [:]

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalParagraphKeyMonitor: Any?
    private var localParagraphKeyMonitor: Any?
    private var debounceWorkItem: DispatchWorkItem?
    private var overlayLayoutRefreshWorkItem: DispatchWorkItem?
    private var lastOcrPosition: CGPoint?
    private var translationServiceInitialized = false
    private let debounceInterval: TimeInterval = 0.1
    private let overlayLayoutRefreshInterval: TimeInterval = 0.04
    private let positionThreshold: CGFloat = 10.0

    private let debugOverlayWindowController = DebugOverlayWindowController()
    private let paragraphHighlightWindowController = ParagraphHighlightWindowController()
    lazy var overlayWindowController = OverlayWindowController(model: self)
    private let startupLanguageAvailabilityRetryDelays: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        3_000_000_000,
    ]

    private var supportsSelectedTextTranslation: Bool {
        DistributionChannel.supportsSelectedTextTranslation
    }

    @MainActor
    init(settings: SettingsStore? = nil, permissions: PermissionManager? = nil, modelContext: ModelContext) {
        let resolvedSettings = settings ?? SettingsStore()
        let resolvedPermissions = permissions ?? PermissionManager()
        self.settings = resolvedSettings
        self.permissions = resolvedPermissions
        self.translationBridge = TranslationBridge()
        self.modelContext = modelContext
        self.dictionaryDownload = DictionaryDownloadManager(offlineService: dictionaryService.offlineService)

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

        if #available(macOS 15.0, *) {
            let manager = LanguagePackManager()
            self.languagePackManager = manager
            // Forward LanguagePackManager changes to AppModel so SwiftUI redraws
            manager.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)

            manager.$languageStatuses
                .sink { [weak self] statuses in
                    self?.syncCachedLanguageStatuses(statuses)
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
        hotkeyManager.onDoubleTap = { [weak self] in
            self?.handleHotkeyDoubleTap()
        }
        hotkeyManager.onPersistentRelease = { [weak self] in
            self?.handlePersistentSentenceOverlayRelease()
        }
        resolvedPermissions.refreshStatus()
        Task {
            await checkLanguageAvailability(notifyUser: false)
        }
    }

    func handleHotkeyTrigger() {
        if #available(macOS 15.0, *) {
            ensureTranslationService()
        }
        isHotkeyActive = true
        activeLookupMode = .word
        isParagraphOverlayPinned = false
        stopParagraphEscapeMonitoring()
        paragraphHighlightWindowController.hide()
        let mouseLocation = NSEvent.mouseLocation
        lastOcrPosition = mouseLocation
        setOverlayAnchor(mouseLocation)
        overlayWindowController.setInteractive(false)
        startMouseTracking()
        startLookup()
    }

    func handleHotkeyRelease() {
        let shouldKeepSentenceOverlayVisible = isParagraphOverlayPinned && isParagraphOverlayPresented

        isHotkeyActive = false
        stopMouseTracking()
        debugOverlayWindowController.hide()
        paragraphHighlightWindowController.hide()

        if shouldKeepSentenceOverlayVisible {
            overlayWindowController.setInteractive(true)
            syncParagraphEscapeMonitoring()
            return
        }

        activeLookupMode = .word
        cancelActiveLookupWork()
        hideOverlay()
    }

    func handlePersistentSentenceOverlayRelease() {
        isHotkeyActive = false
        stopMouseTracking()
        debugOverlayWindowController.hide()
        paragraphHighlightWindowController.hide()

        guard isParagraphOverlayPresented else {
            activeLookupMode = .word
            stopParagraphEscapeMonitoring()
            return
        }

        isParagraphOverlayPinned = true
        overlayWindowController.setInteractive(true)
        syncParagraphEscapeMonitoring()
    }

    func handleHotkeyDoubleTap() {
        guard isHotkeyActive else { return }
        guard settings.ocrSentenceTranslationEnabled else {
            isHotkeyActive = false
            stopMouseTracking()
            cancelActiveLookupWork()
            hideOverlay()
            return
        }
        guard permissions.status.screenRecording else { return }
        if settings.debugShowOcrRegion {
            settings.debugShowOcrRegion = false
            debugOverlayWindowController.hide()
        }
        activeLookupMode = .ocrSentence
        stopMouseTracking()
        let mouseLocation = NSEvent.mouseLocation
        setOverlayAnchor(mouseLocation)
        updateOverlay(state: .paragraphLoading, anchor: mouseLocation)
        startParagraphLookup()
    }

    /// 手动关闭气泡（用于非持续翻译模式）
    func dismissOverlay() {
        activeLookupMode = .word
        isHotkeyActive = false
        stopParagraphEscapeMonitoring()
        cancelActiveLookupWork()
        hideOverlay()
    }

    func toggleParagraphOverlayPin() {
        isParagraphOverlayPinned.toggle()
        if isParagraphOverlayPinned {
            overlayWindowController.setInteractive(true)
        }
    }

    func beginParagraphOverlayDrag() {
        guard isParagraphOverlayPresented, isParagraphOverlayPinned else { return }
        overlayWindowController.beginManualPositioning()
    }

    func updateParagraphOverlayDrag(translation: CGSize) {
        guard isParagraphOverlayPresented, isParagraphOverlayPinned else { return }
        overlayWindowController.moveBy(translation: translation)
    }

    func endParagraphOverlayDrag() {
        guard isParagraphOverlayPresented, isParagraphOverlayPinned else { return }
        overlayWindowController.endManualPositioning()
        refreshParagraphOverlayLayoutImmediately()
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
        guard activeLookupMode == .word else { return }

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
                self.setOverlayAnchor(currentPosition)
                if case .idle = self.overlayState {
                    self.startLookup()
                } else {
                    self.overlayWindowController.move(to: currentPosition)
                    self.startLookup()
                }
            }
        }
        debounceWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func startLookup() {
        activeLookupMode = .word
        cancelActiveLookupWork()
        let lookupID = UUID()
        activeLookupID = lookupID
        lookupTask = Task { [weak self] in
            await self?.performLookup(lookupID: lookupID)
        }
    }

    private func startParagraphLookup() {
        cancelActiveLookupWork()
        let lookupID = UUID()
        activeLookupID = lookupID
        lookupTask = Task { [weak self] in
            await self?.performParagraphLookup(lookupID: lookupID)
        }
    }

    func performLookup(lookupID: UUID) async {
        guard !Task.isCancelled, activeLookupID == lookupID else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard activeLookupID == lookupID else { return }

        switch resolveSinglePressLookupIntent(mouseLocation: mouseLocation) {
        case .selectedTextSentence(let snapshot):
            activeLookupMode = .selectedTextSentence
            await performSelectedTextSentenceLookup(
                snapshot: snapshot,
                lookupID: lookupID,
                mouseLocation: mouseLocation
            )
        case .ocrWord:
            activeLookupMode = .word
            await performOcrWordLookup(
                lookupID: lookupID,
                mouseLocation: mouseLocation
            )
        }
    }

    private func performOcrWordLookup(
        lookupID: UUID,
        mouseLocation: CGPoint
    ) async {
        guard permissions.status.screenRecording else {
            updateOverlay(state: .error(L("Enable Screen Recording")), anchor: mouseLocation)
            return
        }

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
                    hideOverlay()
                }
                return
            }
            guard activeLookupID == lookupID else { return }

            let languagePair = resolveLookupLanguagePair(for: selected.text)
            let sourceLanguage = languagePair.sourceLanguage
            let targetLanguage = languagePair.targetLanguage
            let supportedDictionarySources = dictionarySources(for: languagePair)

            if settings.playWordPronunciation {
                let languageCode = sourceLanguage.languageCode?.identifier
                speechService.speak(
                    selected.text,
                    language: languageCode,
                    provider: settings.wordTTSProvider,
                    useAmericanAccent: settings.englishAccent.isAmerican
                )
            }

            if settings.copyWord {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(selected.text, forType: .string)
            }
            guard !Task.isCancelled, activeLookupID == lookupID else { return }

            let initialContent = makeInitialOverlayContent(
                word: selected.text,
                sources: supportedDictionarySources,
                primaryTranslationState: languagePair.isSameLanguage
                    ? .ready(selected.text, isFallback: false)
                    : .loading
            )
            updateOverlay(state: .result(initialContent), anchor: mouseLocation)

            Task {
                await learningService.recordLookup(word: selected.text)
            }

            await withTaskGroup(of: Void.self) { group in
                if !languagePair.isSameLanguage {
                    if #available(macOS 15.0, *) {
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
                        await Task.yield()
                    }
                }

                for source in supportedDictionarySources {
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

    private func resolveSinglePressLookupIntent(mouseLocation: CGPoint) -> SinglePressLookupIntent {
        debugSelectedTextRoute(
            """
            start mouse=\(describe(point: mouseLocation)) \
            selectedTextSupported=\(supportsSelectedTextTranslation) \
            selectedTextEnabled=\(settings.selectedTextTranslationEnabled) \
            accessibility=\(permissions.status.accessibility) \
            likelySandboxed=\(isLikelySandboxedRuntime()) \
            bundlePath=\(Bundle.main.bundlePath) \
            home=\(NSHomeDirectory()) \
            tmp=\(FileManager.default.temporaryDirectory.path)
            """
        )

        guard supportsSelectedTextTranslation else {
            debugSelectedTextRoute("decision=ocrWord reason=unsupportedChannel")
            return .ocrWord
        }

        guard settings.selectedTextTranslationEnabled else {
            debugSelectedTextRoute("decision=ocrWord reason=featureDisabled")
            return .ocrWord
        }

        guard permissions.status.accessibility else {
            debugSelectedTextRoute("decision=ocrWord reason=missingAccessibility")
            return .ocrWord
        }

        let selectionSnapshot = selectedTextService.currentSelectionSnapshot(mouseLocation: mouseLocation)
        if let selectionSnapshot {
            debugSelectedTextRoute(
                "snapshot text=\"\(truncate(selectionSnapshot.text))\" bounds=\(selectionSnapshot.bounds.map { describe(rect: $0) } ?? "nil") sourceApp=\(selectionSnapshot.sourceAppIdentifier ?? "nil")"
            )
        } else {
            debugSelectedTextRoute("snapshot=nil")
        }

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: mouseLocation,
            isSelectedTextTranslationSupported: supportsSelectedTextTranslation,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: selectionSnapshot
        )
        switch intent {
        case .selectedTextSentence:
            debugSelectedTextRoute("decision=selectedTextSentence")
        case .ocrWord:
            debugSelectedTextRoute("decision=ocrWord")
        }
        return intent
    }

    private func performSelectedTextSentenceLookup(
        snapshot: SelectedTextSnapshot,
        lookupID: UUID,
        mouseLocation: CGPoint
    ) async {
        activeParagraphRect = nil
        overlayPreferredWidth = nil
        paragraphHighlightWindowController.hide()

        let languagePair = resolveParagraphLanguagePair(for: snapshot.text)
        let sourceLanguage = languagePair.sourceLanguage
        let targetLanguage = languagePair.targetLanguage

        if settings.playSentencePronunciation {
            let languageCode = sourceLanguage.languageCode?.identifier
            speechService.speak(
                snapshot.text,
                language: languageCode,
                provider: settings.sentenceTTSProvider,
                useAmericanAccent: settings.englishAccent.isAmerican
            )
        }

        if settings.copySentence {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(snapshot.text, forType: .string)
        }

        let enabledServices = settings.sentenceTranslationSources
            .filter { $0.isEnabled && !$0.isNative }

        let initialContent = ParagraphOverlayContent(
            originalText: snapshot.text,
            translationState: .loading,
            serviceResults: enabledServices.map { source in
                ServiceTranslationResult(sourceType: source.type, state: .loading)
            },
            bodyFontSize: 14,
            useFixedFontSize: true
        )
        updateOverlay(state: .paragraphResult(initialContent), anchor: mouseLocation)

        Task {
            await performThirdPartySentenceTranslations(
                text: snapshot.text,
                sourceLanguage: languagePair.sourceIdentifier,
                targetLanguage: languagePair.targetIdentifier,
                enabledServices: enabledServices,
                lookupID: lookupID,
                anchor: mouseLocation
            )
        }

        let translationState = await loadSentenceTranslationState(
            text: snapshot.text,
            languagePair: languagePair,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            translationBridge: translationBridge
        )

        applyParagraphTranslationState(
            translationState,
            lookupID: lookupID,
            anchor: mouseLocation
        )
    }

    func performParagraphLookup(lookupID: UUID) async {
        guard !Task.isCancelled, activeLookupID == lookupID else { return }
        guard permissions.status.screenRecording else {
            updateOverlay(state: .error(L("Enable Screen Recording")), anchor: NSEvent.mouseLocation)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        updateOverlay(state: .paragraphLoading, anchor: mouseLocation)

        guard let capture = await captureService.captureCurrentDisplay() else {
            paragraphHighlightWindowController.hide()
            updateOverlay(state: .error(L("Capture failed")), anchor: mouseLocation)
            return
        }

        let normalizedPoint = normalizedCursorPoint(mouseLocation, in: capture.region.rect)

        do {
            let (paragraphs, lines) = try await ocrService.recognizeParagraphsWithRawLines(
                in: capture.image,
                language: settings.sourceLanguage
            )
            guard !Task.isCancelled, activeLookupID == lookupID else { return }

            let selectionResult = OCRService.selectParagraphWithLanguageCheck(
                from: paragraphs,
                lines: lines,
                normalizedPoint: normalizedPoint
            )

            switch selectionResult {
            case .noText:
                // No text found near cursor
                paragraphHighlightWindowController.hide()
                let content = ParagraphOverlayContent(
                    originalText: nil,
                    translationState: .failed("No paragraph detected under cursor")
                )
                updateOverlay(state: .paragraphResult(content), anchor: mouseLocation)
                return
            case .english(let paragraph):
                // Found paragraph - continue with translation
                let paragraphRect = screenRect(for: paragraph.boundingBox, in: capture.region.rect)
                let bodyFontSize = OCRService.estimatedDisplayFontSize(
                    for: paragraph,
                    in: capture.region.rect
                )
                paragraphHighlightWindowController.show(at: paragraphRect)

                activeParagraphRect = paragraphRect
                overlayPreferredWidth = max(320, paragraphRect.width)

                let languagePair = resolveParagraphLanguagePair(for: paragraph.text)
                let sourceLanguage = languagePair.sourceLanguage

                if settings.playSentencePronunciation {
                    let languageCode = sourceLanguage.languageCode?.identifier
                    speechService.speak(
                        paragraph.text,
                        language: languageCode,
                        provider: settings.sentenceTTSProvider,
                        useAmericanAccent: settings.englishAccent.isAmerican
                    )
                }

                if settings.copySentence {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(paragraph.text, forType: .string)
                }

                let enabledServices = settings.sentenceTranslationSources
                    .filter { $0.isEnabled && !$0.isNative }

                // Create initial service results with loading state
                let initialServiceResults = enabledServices.map { source in
                    ServiceTranslationResult(sourceType: source.type, state: .loading)
                }

                let initialContent = ParagraphOverlayContent(
                    originalText: paragraph.text,
                    translationState: .loading,
                    serviceResults: initialServiceResults,
                    bodyFontSize: bodyFontSize
                )
                updateOverlay(state: .paragraphResult(initialContent), anchor: mouseLocation)

                let targetLanguage = languagePair.targetLanguage

                // Start third-party translations in parallel
                Task {
                    await performThirdPartySentenceTranslations(
                        text: paragraph.text,
                        sourceLanguage: languagePair.sourceIdentifier,
                        targetLanguage: languagePair.targetIdentifier,
                        enabledServices: enabledServices,
                        lookupID: lookupID,
                        anchor: mouseLocation
                    )
                }

                // Perform native translation
                let translationState = await loadParagraphTranslationState(
                    paragraph: paragraph,
                    languagePair: languagePair,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    translationBridge: translationBridge
                )

                applyParagraphTranslationState(
                    translationState,
                    lookupID: lookupID,
                    anchor: mouseLocation
                )
                return
            }
        } catch is CancellationError {
            paragraphHighlightWindowController.hide()
        } catch {
            paragraphHighlightWindowController.hide()
            let content = ParagraphOverlayContent(
                originalText: nil,
                translationState: .failed("Translation failed: \(error.localizedDescription)")
            )
            updateOverlay(state: .paragraphResult(content), anchor: mouseLocation)
        }
    }

    private func makeInitialOverlayContent(
        word: String,
        sources: [DictionarySource],
        primaryTranslationState: OverlayPrimaryTranslationState
    ) -> OverlayContent {
        let enabledSources = sources.filter(\.isEnabled)

        return OverlayContent(
            word: word,
            phonetic: nil,
            primaryTranslationState: primaryTranslationState,
            usesCompactPrimaryTranslationStyle: !enabledSources.isEmpty,
            dictionarySections: enabledSources.map {
                OverlayDictionarySection(sourceType: $0.type, state: .loading)
            }
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
                return .failed("Translation timeout. Please try again.")
            } catch {
                return .failed("Translation failed: \(error.localizedDescription)")
            }
        } else {
            return .failed("Translation requires macOS 15")
        }
    }

    private func loadParagraphTranslationState(
        paragraph: RecognizedParagraph,
        languagePair: LookupLanguagePair,
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        translationBridge: TranslationBridge
    ) async -> ParagraphOverlayTranslationState {
        let structure = ParagraphTextStructure.fromRecognizedLines(paragraph.lines)
        let sourceText = {
            let renderedText = structure.renderedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return renderedText.isEmpty ? paragraph.text : renderedText
        }()

        if languagePair.isSameLanguage {
            return .ready(sourceText)
        }

        if #available(macOS 15.0, *) {
            let status = await languageAvailabilityStatus(for: languagePair)
            guard status == .installed else {
                return .failed(message(for: status))
            }

            do {
                let translatedText: String

                if !structure.translatableTexts.isEmpty {
                    let translatedBlocks = try await translationBridge.translateBatch(
                        texts: structure.translatableTexts,
                        source: sourceLanguage,
                        target: targetLanguage
                    )

                    if let rebuiltText = structure.applyingTranslations(translatedBlocks)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !rebuiltText.isEmpty {
                        translatedText = rebuiltText
                    } else {
                        translatedText = try await translationBridge.translate(
                            text: sourceText,
                            source: sourceLanguage,
                            target: targetLanguage
                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else {
                    translatedText = try await translationBridge.translate(
                        text: sourceText,
                        source: sourceLanguage,
                        target: targetLanguage
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                return translatedText.isEmpty ? .failed("No translation result") : .ready(translatedText)
            } catch TranslationError.timeout {
                return .failed("Translation timeout. Please try again.")
            } catch {
                return .failed("Translation failed: \(error.localizedDescription)")
            }
        } else {
            return .failed("Translation requires macOS 15")
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

    private func applyParagraphTranslationState(
        _ state: ParagraphOverlayTranslationState,
        lookupID: UUID,
        anchor: CGPoint
    ) {
        updateParagraphOverlayContent(for: lookupID, anchor: anchor) { content in
            content.translationState = state
        }
    }

    private func performThirdPartySentenceTranslations(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        enabledServices: [SentenceTranslationSource],
        lookupID: UUID,
        anchor: CGPoint
    ) async {
        guard !enabledServices.isEmpty else { return }

        await withTaskGroup(of: (SentenceTranslationSource.SourceType, TranslationResultState).self) { group in
            for service in enabledServices {
                group.addTask {
                    do {
                        let result = try await self.sentenceTranslationService.translate(
                            text: text,
                            provider: service.type,
                            sourceLanguage: sourceLanguage,
                            targetLanguage: targetLanguage
                        )

                        if let translation = result, !translation.isEmpty {
                            return (service.type, .ready(translation))
                        } else {
                            return (service.type, .failed(String(localized: "No translation result")))
                        }
                    } catch {
                        let message = "\(String(localized: "Translation failed")): \(error.localizedDescription)"
                        return (service.type, .failed(message))
                    }
                }
            }

            for await (sourceType, state) in group {
                guard !Task.isCancelled, self.activeLookupID == lookupID else { return }

                self.updateParagraphOverlayContent(for: lookupID, anchor: anchor) { content in
                    if let index = content.serviceResults.firstIndex(where: { $0.sourceType == sourceType }) {
                        content.serviceResults[index].state = state
                    }
                }
            }
        }
    }

    private func loadSentenceTranslationState(
        text: String,
        languagePair: LookupLanguagePair,
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        translationBridge: TranslationBridge
    ) async -> ParagraphOverlayTranslationState {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            return .failed("No text selected")
        }

        if languagePair.isSameLanguage {
            return .ready(sourceText)
        }

        if #available(macOS 15.0, *) {
            let status = await languageAvailabilityStatus(for: languagePair)
            guard status == .installed else {
                return .failed(message(for: status))
            }

            do {
                let translatedText = try await translationBridge.translate(
                    text: sourceText,
                    source: sourceLanguage,
                    target: targetLanguage
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                return translatedText.isEmpty ? .failed("No translation result") : .ready(translatedText)
            } catch TranslationError.timeout {
                return .failed("Translation timeout. Please try again.")
            } catch {
                return .failed("Translation failed: \(error.localizedDescription)")
            }
        } else {
            return .failed("Translation requires macOS 15")
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

        let previousContent = content
        mutate(&content)
        guard content != previousContent else { return }
        updateOverlay(state: .result(content), anchor: anchor)
    }

    private func updateFallbackPrimaryTranslation(for content: inout OverlayContent) {
        guard let fallback = content.dictionarySections.lazy.compactMap(\.entry).compactMap(\.primaryTranslation).first else {
            return
        }
        content.primaryTranslationState = .ready(fallback, isFallback: true)
    }

    private func updateParagraphOverlayContent(
        for lookupID: UUID,
        anchor: CGPoint,
        mutate: (inout ParagraphOverlayContent) -> Void
    ) {
        guard activeLookupID == lookupID,
              case .paragraphResult(var content) = overlayState else {
            return
        }

        let previousContent = content
        mutate(&content)
        guard content != previousContent else { return }
        updateOverlay(state: .paragraphResult(content), anchor: anchor)
    }

    func updateOverlay(state: OverlayState, anchor: CGPoint? = nil) {
        guard isHotkeyActive || isParagraphOverlayPresented || !settings.continuousTranslation else { return }

        if let anchor {
            setOverlayAnchor(anchor)
        }

        switch state {
        case .error(let message):
            sendNotification(title: "SnapTra Translator", body: message)
        case .idle:
            break
        case .paragraphLoading, .paragraphResult:
            if overlayState != state {
                overlayState = state
            }
            if overlayWindowController.isVisible {
                refreshParagraphOverlayLayoutImmediately()
            } else {
                overlayWindowController.show(at: overlayAnchor, makeKey: isParagraphOverlayPresented)
            }
            overlayWindowController.setInteractive(true)
        case .result:
            if overlayState != state {
                overlayState = state
            }
            if overlayWindowController.isVisible {
                scheduleOverlayLayoutRefresh()
            } else {
                overlayWindowController.show(at: overlayAnchor, makeKey: isParagraphOverlayPresented)
            }
            if activeLookupMode == .ocrSentence || !settings.continuousTranslation {
                overlayWindowController.setInteractive(true)
            }
        default:
            if overlayState != state {
                overlayState = state
            }
            if overlayWindowController.isVisible {
                scheduleOverlayLayoutRefresh()
            } else {
                overlayWindowController.show(at: overlayAnchor, makeKey: isParagraphOverlayPresented)
            }
            if activeLookupMode == .ocrSentence {
                overlayWindowController.setInteractive(true)
            }
        }

        syncParagraphEscapeMonitoring()
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

        Publishers.CombineLatest3(
            settings.$sourceLanguage,
            settings.$targetLanguage,
            settings.$bidirectionalTranslationEnabled
        )
        .sink { [weak self] _, _, _ in
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
        guard isHotkeyActive || isParagraphOverlayPresented else { return }
        cancelActiveLookupWork()
        hideOverlay()
        debugOverlayWindowController.hide()
    }

    private func restartHotkey() {
        guard !isHotkeyActive else { return }
        hotkeyManager.start(singleKey: settings.singleKey)
    }

    private func handleTranslationSettingsChanged() {
        cancelActiveLookupWork()
        lastAvailabilityKey = nil
        cachedLanguageStatuses.removeAll()

        if overlayState != .idle {
            hideOverlay()
        }

        Task {
            await checkLanguageAvailability()
        }
    }

    private func checkLanguageAvailability(notifyUser: Bool = true) async {
        guard #available(macOS 15.0, *) else { return }
        let pairs = requiredLanguagePairsForCurrentSettings()
        let statusesByKey = await refreshedLanguageAvailabilityStatuses(
            for: pairs,
            retrySupportedStatuses: true
        )

        let key = pairs
            .map { pair in
                let status = statusesByKey[pair.key] ?? .unsupported
                return "\(pair.key)=\(status.rawValue)"
            }
            .joined(separator: "|")

        guard key != lastAvailabilityKey else { return }
        lastAvailabilityKey = key

        guard notifyUser else { return }

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

    private func configuredLanguagePair() -> LookupLanguagePair {
        LookupLanguagePair.fixed(
            sourceIdentifier: settings.sourceLanguage,
            targetIdentifier: settings.targetLanguage
        )
    }

    private func resolveLookupLanguagePair(for observedText: String) -> LookupLanguagePair {
        LookupLanguagePairResolver.resolve(
            configuredPair: configuredLanguagePair(),
            observedText: observedText,
            bidirectionalEnabled: settings.bidirectionalTranslationEnabled
        )
    }

    private func resolveParagraphLanguagePair(for text: String) -> LookupLanguagePair {
        resolveLookupLanguagePair(for: text)
    }

    private func dictionarySources(for pair: LookupLanguagePair) -> [DictionarySource] {
        settings.dictionarySources.filter { source in
            source.isEnabled && source.type.supportsLookup(
                sourceIdentifier: pair.sourceIdentifier,
                targetIdentifier: pair.targetIdentifier
            )
        }
    }

    func requiredLanguagePairsForCurrentSettings() -> [LookupLanguagePair] {
        let pair = configuredLanguagePair()
        var pairs = [pair]

        if settings.bidirectionalTranslationEnabled,
           LookupLanguagePairResolver.supportsBidirectionalDetection(for: pair) {
            pairs.append(pair.reversed())
        }

        var seenKeys = Set<String>()
        return pairs.filter { pair in
            seenKeys.insert(pair.key).inserted
        }
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
            status = await refreshLanguageAvailabilityStatus(for: pair)
        } else {
            status = .unsupported
        }

        cachedLanguageStatuses[pair.key] = status
        return status
    }

    @available(macOS 15.0, *)
    func refreshLanguageAvailabilityStatus(
        from sourceIdentifier: String,
        to targetIdentifier: String,
        showLoading: Bool = false
    ) async -> LanguageAvailability.Status {
        let pair = LookupLanguagePair.fixed(
            sourceIdentifier: sourceIdentifier,
            targetIdentifier: targetIdentifier
        )
        let status = await refreshLanguageAvailabilityStatus(
            for: pair,
            showLoading: showLoading
        )
        return status.translationStatus
    }

    @available(macOS 15.0, *)
    func refreshLanguageAvailabilityStatusForCurrentSettings(
        retryTransientStatus: Bool = false
    ) async -> LanguageAvailability.Status {
        let pairs = requiredLanguagePairsForCurrentSettings()
        var statusesByKey = await refreshedLanguageAvailabilityStatuses(
            for: pairs,
            retrySupportedStatuses: false
        )

        func firstUnavailableStatus() -> CachedLanguageAvailabilityStatus {
            pairs.lazy
                .map { statusesByKey[$0.key] ?? .unsupported }
                .first { $0 != .installed }
                ?? .installed
        }

        var status = firstUnavailableStatus()

        guard retryTransientStatus, status != .installed else {
            return status.translationStatus
        }

        for delay in startupLanguageAvailabilityRetryDelays {
            try? await Task.sleep(nanoseconds: delay)
            statusesByKey = await refreshedLanguageAvailabilityStatuses(
                for: pairs,
                retrySupportedStatuses: false
            )
            status = firstUnavailableStatus()
            if status == .installed {
                break
            }
        }

        return status.translationStatus
    }

    @available(macOS 15.0, *)
    private func refreshedLanguageAvailabilityStatuses(
        for pairs: [LookupLanguagePair],
        retrySupportedStatuses: Bool
    ) async -> [String: CachedLanguageAvailabilityStatus] {
        var statusesByKey: [String: CachedLanguageAvailabilityStatus] = [:]

        for pair in pairs {
            statusesByKey[pair.key] = await refreshLanguageAvailabilityStatus(for: pair)
        }

        guard retrySupportedStatuses else {
            return statusesByKey
        }

        let supportedPairs = pairs.filter { statusesByKey[$0.key] == .supported }
        guard !supportedPairs.isEmpty else {
            return statusesByKey
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        for pair in supportedPairs {
            statusesByKey[pair.key] = await refreshLanguageAvailabilityStatus(for: pair)
        }

        return statusesByKey
    }

    @available(macOS 15.0, *)
    private func refreshLanguageAvailabilityStatus(
        for pair: LookupLanguagePair,
        showLoading: Bool = false
    ) async -> CachedLanguageAvailabilityStatus {
        if pair.isSameLanguage {
            cachedLanguageStatuses[pair.key] = .installed
            return .installed
        }

        let status: CachedLanguageAvailabilityStatus
        if let manager = languagePackManager {
            let systemStatus: LanguageAvailability.Status
            if showLoading {
                systemStatus = await manager.checkLanguagePair(
                    from: pair.sourceIdentifier,
                    to: pair.targetIdentifier
                )
            } else {
                systemStatus = await manager.checkLanguagePairQuiet(
                    from: pair.sourceIdentifier,
                    to: pair.targetIdentifier
                )
            }
            status = CachedLanguageAvailabilityStatus(systemStatus)
        } else {
            let availability = LanguageAvailability()
            let systemStatus = await availability.status(from: pair.sourceLanguage, to: pair.targetLanguage)
            status = CachedLanguageAvailabilityStatus(systemStatus)
        }

        cachedLanguageStatuses[pair.key] = status
        return status
    }

    @available(macOS 15.0, *)
    private func syncCachedLanguageStatuses(_ statuses: [String: LanguageAvailability.Status]) {
        for (key, status) in statuses {
            cachedLanguageStatuses[key] = CachedLanguageAvailabilityStatus(status)
        }
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

    private func screenRect(for normalizedRect: CGRect, in captureRect: CGRect) -> CGRect {
        CGRect(
            x: captureRect.minX + normalizedRect.minX * captureRect.width,
            y: captureRect.minY + normalizedRect.minY * captureRect.height,
            width: normalizedRect.width * captureRect.width,
            height: normalizedRect.height * captureRect.height
        )
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
        let entry: DictionaryEntry
        do {
            guard let lookedUpEntry = try await dictionaryService.lookupSingle(
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
            entry = lookedUpEntry
        } catch {
            return DictionarySectionResult(
                sourceType: source.type,
                state: .failed(error.localizedDescription),
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
        let sourceIsEnglish = sourceLanguage.minimalIdentifier == "en"
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

                    if let englishFastPathTranslation = englishFastPathTranslation(
                        for: def,
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage
                    ) {
                        return (index, DictionaryEntry.Definition(
                            partOfSpeech: def.partOfSpeech,
                            field: def.field,
                            meaning: def.meaning,
                            translation: englishFastPathTranslation,
                            examples: def.examples
                        ))
                    }

                    if targetIsEnglish && sourceIsEnglish {
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
                    } else if targetIsEnglish && sourceIsEnglish {
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

    nonisolated static func englishFastPathTranslation(
        for definition: DictionaryEntry.Definition,
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language
    ) -> String? {
        guard sourceLanguage.minimalIdentifier == "en",
              targetLanguage.minimalIdentifier == "en" else {
            return nil
        }

        let trimmedMeaning = definition.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEnglishContent = trimmedMeaning.range(of: "[a-zA-Z]{3,}", options: .regularExpression) != nil
        return hasEnglishContent ? trimmedMeaning : nil
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

    private func cancelActiveLookupWork() {
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        translationBridge.cancelAllPendingRequests()
        cancelPendingOverlayLayoutRefresh()
    }

    private func hideOverlay() {
        activeLookupMode = .word
        isParagraphOverlayPinned = false
        stopParagraphEscapeMonitoring()
        cancelPendingOverlayLayoutRefresh()
        speechService.stopSpeaking()
        cachedLanguageStatuses.removeAll(keepingCapacity: false)
        if overlayState != .idle {
            overlayState = .idle
        }
        activeParagraphRect = nil
        overlayPreferredWidth = nil
        paragraphHighlightWindowController.hide()
        overlayWindowController.setInteractive(false)
        overlayWindowController.hide()
    }

    @available(macOS 15.0, *)
    private func ensureTranslationService() {
        guard !translationServiceInitialized else { return }
        translationServiceInitialized = true
        createTranslationServiceWindowIfNeeded()
        warmupTranslationService()
    }

    @available(macOS 15.0, *)
    private func createTranslationServiceWindowIfNeeded() {
        guard TranslationServiceWindowHolder.shared.window == nil else { return }

        let translationView = TranslationBridgeView(bridge: translationBridge)
        let hostingView = NSHostingView(rootView: translationView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setIsVisible(false)

        TranslationServiceWindowHolder.shared.window = window
    }

    @available(macOS 15.0, *)
    private func warmupTranslationService() {
        Task { @MainActor in
            let sourceLanguage = Locale.Language(identifier: settings.sourceLanguage)
            let targetLanguage = Locale.Language(identifier: settings.targetLanguage)

            _ = try? await translationBridge.translate(
                text: "hello",
                source: sourceLanguage,
                target: targetLanguage,
                timeout: 10.0
            )
        }
    }

    private func setOverlayAnchor(_ anchor: CGPoint) {
        guard overlayAnchor != anchor else { return }
        overlayAnchor = anchor
    }

    private func scheduleOverlayLayoutRefresh() {
        guard overlayWindowController.isVisible else { return }

        cancelPendingOverlayLayoutRefresh()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.overlayLayoutRefreshWorkItem = nil
                guard let self else { return }
                guard self.overlayWindowController.isVisible else { return }
                self.refreshParagraphOverlayLayout(animated: false)
            }
        }

        overlayLayoutRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + overlayLayoutRefreshInterval, execute: workItem)
    }

    private func cancelPendingOverlayLayoutRefresh() {
        overlayLayoutRefreshWorkItem?.cancel()
        overlayLayoutRefreshWorkItem = nil
    }

    private func refreshParagraphOverlayLayoutImmediately() {
        guard overlayWindowController.isVisible else { return }

        cancelPendingOverlayLayoutRefresh()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.overlayWindowController.isVisible else { return }
            self.refreshParagraphOverlayLayout(animated: true)
        }
    }

    private func refreshParagraphOverlayLayout(animated: Bool) {
        if overlayWindowController.isManualParagraphPositioningActive {
            return
        }

        if overlayWindowController.hasManualParagraphPosition {
            overlayWindowController.refreshLayoutIfNeeded(at: overlayAnchor)
            return
        }

        if let sentenceRect = activeParagraphRect {
            overlayWindowController.alignToSentenceRect(sentenceRect, animated: animated)
        } else {
            overlayWindowController.refreshLayoutIfNeeded(at: overlayAnchor)
        }
    }

    private var isParagraphOverlayPresented: Bool {
        switch overlayState {
        case .paragraphLoading, .paragraphResult:
            return true
        default:
            return false
        }
    }

    private func syncParagraphEscapeMonitoring() {
        if isParagraphOverlayPresented {
            startParagraphEscapeMonitoringIfNeeded()
        } else {
            stopParagraphEscapeMonitoring()
        }
    }

    private func startParagraphEscapeMonitoringIfNeeded() {
        guard globalParagraphKeyMonitor == nil, localParagraphKeyMonitor == nil else { return }

        globalParagraphKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                _ = self?.handleParagraphEscapeKey(event)
            }
        }

        localParagraphKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated {
                self.handleParagraphEscapeKey(event)
            }
            return handled ? nil : event
        }
    }

    private func stopParagraphEscapeMonitoring() {
        if let monitor = globalParagraphKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalParagraphKeyMonitor = nil
        }

        if let monitor = localParagraphKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localParagraphKeyMonitor = nil
        }
    }

    @discardableResult
    private func handleParagraphEscapeKey(_ event: NSEvent) -> Bool {
        guard isParagraphOverlayPresented else { return false }
        guard event.keyCode == 53 else { return false }
        dismissOverlay()
        return true
    }

    private func debugSelectedTextRoute(_ message: String) {
#if DEBUG
        print("[SelectedTextRoute] \(message)")
#endif
    }

    private func isLikelySandboxedRuntime() -> Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }

    private func describe(point: CGPoint) -> String {
        "(\(format(point.x)), \(format(point.y)))"
    }

    private func describe(rect: CGRect) -> String {
        "x=\(format(rect.origin.x)) y=\(format(rect.origin.y)) w=\(format(rect.width)) h=\(format(rect.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func truncate(_ text: String, limit: Int = 120) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }
}
