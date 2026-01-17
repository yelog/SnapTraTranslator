import Foundation

enum ProductID {
    static let trial = "org.yelog.SnapTranslate.trial"
    static let lifetime = "org.yelog.SnapTranslate.lifetime"
    
    static let all: [String] = [trial, lifetime]
}

enum TrialConfig {
    static let durationDays = 30
}

extension Notification.Name {
    static let showPaywall = Notification.Name("showPaywall")
}
