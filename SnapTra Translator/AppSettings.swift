import Foundation

enum SingleKey: String, CaseIterable, Identifiable {
    case leftShift
    case leftControl
    case leftOption
    case leftCommand
    case rightShift
    case rightControl
    case rightOption
    case rightCommand
    case fn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftShift:
            return L("Left Shift")
        case .leftControl:
            return L("Left Control")
        case .leftOption:
            return L("Left Option")
        case .leftCommand:
            return L("Left Command")
        case .rightShift:
            return L("Right Shift")
        case .rightControl:
            return L("Right Control")
        case .rightOption:
            return L("Right Option")
        case .rightCommand:
            return L("Right Command")
        case .fn:
            return "Fn"
        }
    }
}

enum TTSProvider: String, CaseIterable, Identifiable {
    case apple = "apple"
    case youdao = "youdao"
    case bing = "bing"
    case google = "google"
    case baidu = "baidu"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:
            return L("Apple")
        case .youdao:
            return L("Youdao")
        case .bing:
            return L("Bing")
        case .google:
            return L("Google")
        case .baidu:
            return L("Baidu")
        }
    }

    var requiresNetwork: Bool {
        self != .apple
    }

    var description: String {
        switch self {
        case .apple:
            return L("System built-in, works offline")
        case .youdao:
            return L("Clear word pronunciation")
        case .bing:
            return L("High quality neural voice")
        case .google:
            return L("Google Translate voice")
        case .baidu:
            return L("Natural pronunciation")
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return L("Follow System")
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        case .spanish:
            return "Español"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        default:
            return rawValue
        }
    }
}

enum AppSettingKey {
    static let playPronunciation = "playPronunciation"
    static let launchAtLogin = "launchAtLogin"
    static let singleKey = "singleKey"
    static let sourceLanguage = "sourceLanguage"
    static let targetLanguage = "targetLanguage"
    static let debugShowOcrRegion = "debugShowOcrRegion"
    static let continuousTranslation = "continuousTranslation"
    static let lastScreenRecordingStatus = "lastScreenRecordingStatus"
    static let ttsProvider = "ttsProvider"
    static let appLanguage = "appLanguage"
    static let englishAccent = "englishAccent"
    static let sentenceTranslationEnabled = "sentenceTranslationEnabled"
}

enum EnglishAccent: String, CaseIterable, Identifiable {
    case american = "en-US"
    case british = "en-GB"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .american:
            return L("American (US)")
        case .british:
            return L("British (UK)")
        }
    }
    
    var isAmerican: Bool {
        self == .american
    }
}
