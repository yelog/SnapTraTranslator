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
            return "Left Shift"
        case .leftControl:
            return "Left Ctrl"
        case .leftOption:
            return "Left Opt"
        case .leftCommand:
            return "Left Cmd"
        case .rightShift:
            return "Right Shift"
        case .rightControl:
            return "Right Ctrl"
        case .rightOption:
            return "Right Opt"
        case .rightCommand:
            return "Right Cmd"
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
