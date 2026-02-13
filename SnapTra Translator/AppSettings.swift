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
            return String(localized: "Left Shift")
        case .leftControl:
            return String(localized: "Left Control")
        case .leftOption:
            return String(localized: "Left Option")
        case .leftCommand:
            return String(localized: "Left Command")
        case .rightShift:
            return String(localized: "Right Shift")
        case .rightControl:
            return String(localized: "Right Control")
        case .rightOption:
            return String(localized: "Right Option")
        case .rightCommand:
            return String(localized: "Right Command")
        case .fn:
            return "Fn"
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
}
