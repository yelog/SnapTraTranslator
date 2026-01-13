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
}

enum OverlayState: Equatable {
    case idle
    case loading(String?)
    case result(OverlayContent)
    case error(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var overlayState: OverlayState = .idle
    @Published var overlayAnchor: CGPoint = .zero

    @Published var settings: SettingsStore
    let permissions: PermissionManager
    let translationBridge: TranslationBridge

    private let hotkeyManager = HotkeyManager()
    private let captureService = ScreenCaptureService()
    private let ocrService = OCRService()
    private let phoneticService = PhoneticService()
    private let speechService = SpeechService()
    private var cancellables = Set<AnyCancellable>()
    private var lookupTask: Task<Void, Never>?
    private var activeLookupID: UUID?
    private var isHotkeyActive = false
    private var lastAvailabilityKey: String?

    private let debugOverlayWindowController = DebugOverlayWindowController()
    lazy var overlayWindowController = OverlayWindowController(model: self)

    @MainActor
    init(settings: SettingsStore? = nil, permissions: PermissionManager? = nil) {
        let resolvedSettings = settings ?? SettingsStore()
        let resolvedPermissions = permissions ?? PermissionManager()
        self.settings = resolvedSettings
        self.permissions = resolvedPermissions
        self.translationBridge = TranslationBridge()
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
        Task { await checkLanguageAvailability() }
    }

    func handleHotkeyTrigger() {
        isHotkeyActive = true
        startLookup()
    }

    func handleHotkeyRelease() {
        isHotkeyActive = false
        lookupTask?.cancel()
        lookupTask = nil
        activeLookupID = nil
        overlayState = .idle
        overlayWindowController.hide()
        debugOverlayWindowController.hide()
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
        await permissions.refreshStatusAsync()
        guard !Task.isCancelled, activeLookupID == lookupID else { return }
        guard permissions.status.screenRecording else {
            updateOverlay(state: .error("Enable Screen Recording"))
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        guard activeLookupID == lookupID else { return }
        updateOverlay(state: .loading(nil), anchor: mouseLocation)
        guard let capture = await captureService.captureAroundCursor() else {
            debugOverlayWindowController.hide()
            updateOverlay(state: .error("Capture failed"), anchor: mouseLocation)
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
            let words = try await ocrService.recognizeWords(in: capture.image)
            guard !Task.isCancelled, activeLookupID == lookupID else { return }
            guard let selected = selectWord(from: words, normalizedPoint: normalizedPoint) else {
                updateOverlay(state: .error("No word detected"), anchor: mouseLocation)
                return
            }
            guard activeLookupID == lookupID else { return }
            updateOverlay(state: .loading(selected.text), anchor: mouseLocation)
            guard !Task.isCancelled, activeLookupID == lookupID else { return }
            let phonetic = phoneticService.phonetic(for: selected.text)
            let sourceLanguage = Locale.Language(identifier: settings.sourceLanguage)
            let targetLanguage = Locale.Language(identifier: settings.targetLanguage)
            if #available(macOS 15.0, *) {
                let availability = LanguageAvailability()
                let status = await availability.status(from: sourceLanguage, to: targetLanguage)
                guard status == .installed else {
                    let message = status == .supported
                        ? "Language pack required. Please download in System Settings > General > Language & Region > Translation."
                        : "Translation not supported for this language pair."
                    updateOverlay(state: .error(message), anchor: mouseLocation)
                    return
                }
                let translated = try await translationBridge.translate(text: selected.text, source: sourceLanguage, target: targetLanguage)
                guard !Task.isCancelled, activeLookupID == lookupID else { return }
                let content = OverlayContent(word: selected.text, phonetic: phonetic, translation: translated)
                updateOverlay(state: .result(content), anchor: mouseLocation)
                if settings.playPronunciation {
                    let languageCode = sourceLanguage.languageCode?.identifier
                    speechService.speak(selected.text, language: languageCode)
                }
            } else {
                updateOverlay(state: .error("Translation requires macOS 15"), anchor: mouseLocation)
            }
        } catch {
            updateOverlay(state: .error("OCR or translation failed"), anchor: mouseLocation)
        }
    }

    func updateOverlay(state: OverlayState, anchor: CGPoint? = nil) {
        if let anchor {
            overlayAnchor = anchor
        }
        switch state {
        case .error(let message):
            sendNotification(title: "Snap Translate", body: message)
        case .idle:
            break
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
                Task { await self?.checkLanguageAvailability() }
            }
            .store(in: &cancellables)

        permissions.$status
            .sink { [weak self] status in
                if status.inputMonitoring {
                    self?.restartHotkey()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.restartHotkey()
            }
            .store(in: &cancellables)
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
        let key = "\(sourceLanguage.minimalIdentifier)->\(targetLanguage.minimalIdentifier)-\(status)"
        guard key != lastAvailabilityKey else { return }
        lastAvailabilityKey = key
        switch status {
        case .installed:
            break
        case .supported:
            sendNotification(title: "Snap Translate", body: "Language pack required. Please download in System Settings > General > Language & Region > Translation.")
        case .unsupported:
            sendNotification(title: "Snap Translate", body: "Translation not supported for this language pair.")
        @unknown default:
            break
        }
    }

    private func normalizedCursorPoint(_ mouseLocation: CGPoint, in rect: CGRect) -> CGPoint {
        let x = (mouseLocation.x - rect.minX) / rect.width
        let y = (mouseLocation.y - rect.minY) / rect.height
        return CGPoint(x: x, y: y)
    }

    private func selectWord(from words: [RecognizedWord], normalizedPoint: CGPoint) -> RecognizedWord? {
        if let direct = words.first(where: { $0.boundingBox.contains(normalizedPoint) }) {
            return direct
        }
        return words.min { lhs, rhs in
            let leftDistance = distance(from: normalizedPoint, to: lhs.boundingBox)
            let rightDistance = distance(from: normalizedPoint, to: rhs.boundingBox)
            return leftDistance < rightDistance
        }
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return sqrt(dx * dx + dy * dy)
    }
}
