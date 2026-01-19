import Foundation

enum ProductID {
    static let lifetime = "org.yelog.SnapTranslate.lifetime"

    static let all: [String] = [lifetime]
}

enum TrialConfig {
    static let durationDays = 7
}

extension Notification.Name {
    static let showPaywall = Notification.Name("showPaywall")
}
