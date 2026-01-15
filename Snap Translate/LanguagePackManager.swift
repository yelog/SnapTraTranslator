import AppKit
import Combine
import Foundation
import Translation

@available(macOS 15.0, *)
@MainActor
final class LanguagePackManager: ObservableObject {
    @Published var languageStatuses: [String: LanguageAvailability.Status] = [:]

    private let availability = LanguageAvailability()
    private let commonLanguages: [String] = [
        "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "it", "pt", "ru", "ar", "th", "vi"
    ]
    private var refreshTimer: Timer?

    init() {
        // 创建定时器，每5秒检查一次语言包状态（当应用在前台时）
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshCurrentLanguages()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private var currentSourceLanguage: String?

    private func refreshCurrentLanguages() async {
        guard let source = currentSourceLanguage else { return }
        await checkAllLanguages(from: source)
    }

    /// 检查所有常用语言对的可用性
    func checkAllLanguages(from sourceLanguage: String) async {
        currentSourceLanguage = sourceLanguage
        for targetLang in commonLanguages {
            if sourceLanguage == targetLang { continue }

            let source = Locale.Language(identifier: sourceLanguage)
            let target = Locale.Language(identifier: targetLang)

            let status = await availability.status(from: source, to: target)
            languageStatuses["\(sourceLanguage)->\(targetLang)"] = status
        }
    }

    /// 检查特定语言对的可用性
    func checkLanguagePair(from sourceLanguage: String, to targetLanguage: String) async -> LanguageAvailability.Status {
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)
        let status = await availability.status(from: source, to: target)
        languageStatuses["\(sourceLanguage)->\(targetLanguage)"] = status
        return status
    }

    /// 获取特定语言对的状态
    func getStatus(from sourceLanguage: String, to targetLanguage: String) -> LanguageAvailability.Status? {
        return languageStatuses["\(sourceLanguage)->\(targetLanguage)"]
    }

    /// 打开系统设置的翻译语言下载页面
    func openTranslationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
