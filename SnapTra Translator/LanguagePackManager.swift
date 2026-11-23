import AppKit
import Combine
import Foundation
import Translation

@available(macOS 15.0, *)
@MainActor
final class LanguagePackManager: ObservableObject {
    @Published private var languageStatuses: [AppleTranslationStrategy: [String: LanguageAvailability.Status]] = [:]
    @Published var isChecking: Bool = false

    private let fastAvailability = AppleTranslationStrategy.fast.makeLanguageAvailability()
    private lazy var qualityAvailability = AppleTranslationStrategy.qualityPreferred.makeLanguageAvailability()
    private let commonLanguages: [String] = [
        "zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "it", "pt", "ru", "ar", "th", "vi"
    ]
    private var currentSourceLanguage: String?

    /// 检查所有常用语言对的可用性
    func checkAllLanguages(from sourceLanguage: String) async {
        await MainActor.run {
            isChecking = true
            currentSourceLanguage = sourceLanguage
            objectWillChange.send()
        }

        for targetLang in commonLanguages {
            if sourceLanguage == targetLang { continue }
            _ = await checkLanguagePairQuiet(from: sourceLanguage, to: targetLang)
        }

        await MainActor.run {
            isChecking = false
            objectWillChange.send()
        }
    }

    /// 检查特定语言对的可用性
    func checkLanguagePair(
        from sourceLanguage: String,
        to targetLanguage: String,
        strategy: AppleTranslationStrategy = .fast
    ) async -> LanguageAvailability.Status {
        isChecking = true
        defer { isChecking = false }
        return await checkLanguagePairQuiet(from: sourceLanguage, to: targetLanguage, strategy: strategy)
    }

    /// 快速检查单个语言对（不显示 loading 状态）
    func checkLanguagePairQuiet(
        from sourceLanguage: String,
        to targetLanguage: String,
        strategy: AppleTranslationStrategy = .fast
    ) async -> LanguageAvailability.Status {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: sourceLanguage, targetIdentifier: targetLanguage)
        let availability = strategy == .fast ? fastAvailability : qualityAvailability
        let status = await availability.status(from: pair.sourceLanguage, to: pair.targetLanguage)
        if languageStatuses[strategy]?[pair.key] != status {
            languageStatuses[strategy, default: [:]][pair.key] = status
        }
        return status
    }

    /// 获取特定语言对的状态
    func getStatus(
        from sourceLanguage: String,
        to targetLanguage: String,
        strategy: AppleTranslationStrategy = .fast
    ) -> LanguageAvailability.Status? {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: sourceLanguage, targetIdentifier: targetLanguage)
        return languageStatuses[strategy]?[pair.key]
    }

    /// 打开系统设置的翻译语言下载页面
    func openTranslationSettings() {
        // 尝试多种方式打开翻译语言设置

        // 方式1: 尝试直接打开翻译语言设置
        let translationURL = "x-apple.systempreferences:com.apple.Localization-Settings.extension?Translation"
        if let url = URL(string: translationURL) {
            NSWorkspace.shared.open(url)
            return
        }

        // 方式2: 使用 AppleScript 打开并尝试点击 Translation Languages 按钮
        let script = """
        tell application "System Settings"
            activate
            delay 0.5
            reveal pane id "com.apple.Localization-Settings.extension"
        end tell

        tell application "System Events"
            tell process "System Settings"
                try
                    delay 0.5
                    -- 尝试点击 "Translation Languages..." 按钮
                    click button "Translation Languages…" of group 1 of scroll area 1 of group 1 of group 2 of splitter group 1 of group 1 of window 1
                on error
                    -- 如果找不到按钮，至少已经打开了 Language & Region 面板
                end try
            end tell
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error == nil {
                return
            }
        }

        // 方式3: 降级到只打开 Language & Region
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
