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
    var definitions: [DictionaryEntry.Definition]

    init(word: String, phonetic: String?, translation: String, definitions: [DictionaryEntry.Definition] = []) {
        self.word = word
        self.phonetic = phonetic
        self.translation = translation
        self.definitions = definitions
    }
}

enum OverlayState: Equatable {
    case idle
    case loading(String?)
    case result(OverlayContent)
    case error(String)
    case noWord
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
    private var cancellables = Set<AnyCancellable>()
    private var lookupTask: Task<Void, Never>?
    private var activeLookupID: UUID?
    private var isHotkeyActive = false
    private var lastAvailabilityKey: String?
    private var cachedLanguageStatus: (key: String, isInstalled: Bool)?
    
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
            updateOverlay(state: .error(String(localized: "Enable Screen Recording")), anchor: NSEvent.mouseLocation)
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
                updateOverlay(state: .error(String(localized: "Capture failed")), anchor: mouseLocation)
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
            let words = try await ocrService.recognizeWords(in: capture.image, language: settings.sourceLanguage)
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
            let sourceLanguage = Locale.Language(identifier: settings.sourceLanguage)
            let targetLanguage = Locale.Language(identifier: settings.targetLanguage)
            if settings.playPronunciation {
                let languageCode = sourceLanguage.languageCode?.identifier
                speechService.speak(selected.text, language: languageCode)
            }
            guard !Task.isCancelled, activeLookupID == lookupID else { return }

            let targetIsEnglish = targetLanguage.minimalIdentifier == "en"
            let dictEntry = dictionaryService.lookup(selected.text, preferEnglish: targetIsEnglish)
            let phonetic = dictEntry?.phonetic
            var definitions = dictEntry?.definitions ?? []

            if sourceLanguage.minimalIdentifier == targetLanguage.minimalIdentifier {
                var processedDefinitions = definitions
                let isEnglish = sourceLanguage.minimalIdentifier == "en"
                
                if isEnglish && !definitions.isEmpty {
                    processedDefinitions = definitions.compactMap { def in
                        let trimmedMeaning = def.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                        let hasEnglishContent = trimmedMeaning.range(of: "[a-zA-Z]{3,}", options: .regularExpression) != nil
                        guard hasEnglishContent else { return nil }
                        return DictionaryEntry.Definition(
                            partOfSpeech: def.partOfSpeech,
                            meaning: def.meaning,
                            translation: trimmedMeaning,
                            examples: def.examples
                        )
                    }
                }
                
                let content = OverlayContent(
                    word: selected.text,
                    phonetic: phonetic,
                    translation: selected.text,
                    definitions: processedDefinitions
                )
                updateOverlay(state: .result(content), anchor: mouseLocation)
                return
            }

            if #available(macOS 15.0, *) {
                let languageKey = "\(sourceLanguage.minimalIdentifier)->\(targetLanguage.minimalIdentifier)"
                
                let isInstalled: Bool
                if let cached = cachedLanguageStatus, cached.key == languageKey {
                    isInstalled = cached.isInstalled
                } else {
                    let availability = LanguageAvailability()
                    let status = await availability.status(from: sourceLanguage, to: targetLanguage)
                    isInstalled = status == .installed
                    cachedLanguageStatus = (languageKey, isInstalled)
                    
                    if !isInstalled {
                        let message = status == .supported
                            ? String(localized: "Language pack required. Please download in System Settings > General > Language & Region > Translation.")
                            : String(localized: "Translation not supported for this language pair.")
                        updateOverlay(state: .error(message), anchor: mouseLocation)
                        return
                    }
                }
                
                guard isInstalled else {
                    updateOverlay(state: .error(String(localized: "Language pack not installed.")), anchor: mouseLocation)
                    return
                }

                // 翻译单词
                let translated = try await translationBridge.translate(text: selected.text, source: sourceLanguage, target: targetLanguage)
                guard !Task.isCancelled, activeLookupID == lookupID else { return }

                // 如果词典有释义，根据目标语言处理每个释义
                if !definitions.isEmpty {
                    definitions = await translateDefinitionsInParallel(
                        definitions: definitions,
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage
                    )
                }

                let content = OverlayContent(
                    word: selected.text,
                    phonetic: phonetic,
                    translation: translated,
                    definitions: definitions
                )
                updateOverlay(state: .result(content), anchor: mouseLocation)
            } else {
                updateOverlay(state: .error(String(localized: "Translation requires macOS 15")), anchor: mouseLocation)
            }
        } catch is CancellationError {
            // Task was cancelled, do nothing
        } catch TranslationError.timeout {
            updateOverlay(state: .error(String(localized: "Translation timeout. Please try again.")), anchor: mouseLocation)
        } catch {
            updateOverlay(state: .error(String(localized: "Translation failed: \(error.localizedDescription)")), anchor: mouseLocation)
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

        settings.$sourceLanguage
            .combineLatest(settings.$targetLanguage)
            .sink { [weak self] _, _ in
                guard let self = self else { return }
                // Cancel any ongoing translation when language changes
                self.lookupTask?.cancel()
                self.lookupTask = nil
                self.activeLookupID = nil
                if self.overlayState != .idle {
                    self.overlayState = .idle
                }
                Task {
                    await self.checkLanguageAvailability()
                }
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

    private func checkLanguageAvailability() async {
        guard #available(macOS 15.0, *) else { return }
        let sourceLanguage = Locale.Language(identifier: settings.sourceLanguage)
        let targetLanguage = Locale.Language(identifier: settings.targetLanguage)
        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLanguage, to: targetLanguage)
        let languageKey = "\(sourceLanguage.minimalIdentifier)->\(targetLanguage.minimalIdentifier)"
        let key = "\(languageKey)-\(status)"
        
        cachedLanguageStatus = (languageKey, status == .installed)
        
        guard key != lastAvailabilityKey else { return }
        lastAvailabilityKey = key
        switch status {
        case .installed:
            break
        case .supported:
            sendNotification(title: String(localized: "SnapTra Translator"), body: String(localized: "Language pack required. Please download in System Settings > General > Language & Region > Translation."))
        case .unsupported:
            sendNotification(title: String(localized: "SnapTra Translator"), body: String(localized: "Translation not supported for this language pair."))
        @unknown default:
            break
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
