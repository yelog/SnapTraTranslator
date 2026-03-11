import Combine
import Foundation
import SwiftUI

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage = .system
    
    /// Custom bundle for the current language
    private var currentBundle: Bundle = .main
    
    private init() {
        // Load saved language preference
        let savedLanguage = UserDefaults.standard.string(forKey: AppSettingKey.appLanguage)
        if let saved = savedLanguage,
           let language = AppLanguage(rawValue: saved) {
            currentLanguage = language
            updateBundle(for: language)
            applyLanguage(language)
        }
    }
    
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        updateBundle(for: language)
        applyLanguage(language)
        
        // Post notification for views to update
        NotificationCenter.default.post(name: .languageChanged, object: nil)
    }
    
    private func updateBundle(for language: AppLanguage) {
        guard let identifier = language.localeIdentifier else {
            // "Follow System": resolve the actual system language,
            // bypassing any app-level AppleLanguages override.
            if let sysLang = systemLanguageIdentifier(),
               let path = Bundle.main.path(forResource: sysLang, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                currentBundle = bundle
            } else if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
                      let bundle = Bundle(path: path) {
                currentBundle = bundle
            } else {
                currentBundle = .main
            }
            return
        }

        if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            currentBundle = bundle
        } else {
            currentBundle = .main
        }
    }

    /// Returns the best matching localization for the system language,
    /// reading from the global (non-app) AppleLanguages preference.
    private func systemLanguageIdentifier() -> String? {
        guard let systemLanguages = CFPreferencesCopyValue(
            "AppleLanguages" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String] else {
            return nil
        }

        let available = Bundle.main.localizations.filter { $0 != "Base" }
        return Bundle.preferredLocalizations(from: available, forPreferences: systemLanguages).first
    }
    
    private func applyLanguage(_ language: AppLanguage) {
        guard let identifier = language.localeIdentifier else {
            // Reset to system default
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            return
        }
        
        // Set the language preference for next launch
        UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
    
    /// Get localized string with current language context (real-time)
    func localizedString(_ key: String) -> String {
        return NSLocalizedString(key, tableName: nil, bundle: currentBundle, value: key, comment: "")
    }
    
    /// Get localized string with format arguments (variadic)
    func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedString(key)
        return String(format: format, arguments: arguments)
    }
    
    /// Get localized string with format arguments (array)
    func localizedString(_ key: String, _ arguments: [CVarArg]) -> String {
        let format = localizedString(key)
        return String(format: format, arguments: arguments)
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
}

// MARK: - SwiftUI Environment

private struct LanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = LocalizationManager.shared
}

extension EnvironmentValues {
    var localizationManager: LocalizationManager {
        get { self[LanguageEnvironmentKey.self] }
        set { self[LanguageEnvironmentKey.self] = newValue }
    }
}

// MARK: - Convenience Helper

/// Helper function to get localized string that responds to language changes
func L(_ key: String) -> String {
    return LocalizationManager.shared.localizedString(key)
}

/// Helper function to get localized string with format arguments
func L(_ key: String, _ arguments: CVarArg...) -> String {
    return LocalizationManager.shared.localizedString(key, arguments)
}

// MARK: - Localized Text Component

struct LocalizedText: View {
    let key: String
    @StateObject private var manager = LocalizationManager.shared
    
    init(_ key: String) {
        self.key = key
    }
    
    var body: some View {
        Text(manager.localizedString(key))
            .id(manager.currentLanguage.rawValue + key)
    }
}

// MARK: - View Extension for Real-time Localization

struct RealtimeLocalizationModifier: ViewModifier {
    @StateObject private var manager = LocalizationManager.shared
    
    func body(content: Content) -> some View {
        content
            .environment(\.localizationManager, manager)
            .id("lang-\(manager.currentLanguage.rawValue)")
    }
}

extension View {
    func withRealtimeLocalization() -> some View {
        self.modifier(RealtimeLocalizationModifier())
    }
}
