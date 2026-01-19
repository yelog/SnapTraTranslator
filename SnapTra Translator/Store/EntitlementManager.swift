import Foundation
import Combine

enum UserEntitlement: Equatable {
    case noTrial
    case trialActive(daysRemaining: Int)
    case trialExpired
    case lifetime
}

@MainActor
final class EntitlementManager: ObservableObject {
    static let shared = EntitlementManager()
    
    @Published private(set) var entitlement: UserEntitlement = .noTrial
    @Published private(set) var isUnlocked = false
    
    private let storeKit = StoreKitManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private var bypassLicenseCheck: Bool {
        #if DEBUG
        return true
        #else
        return isAppStoreReviewBuild
        #endif
    }
    
    private var isAppStoreReviewBuild: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }
    
    private init() {
        setupBindings()
        updateEntitlement()
    }
    
    private func setupBindings() {
        storeKit.$purchasedProductIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateEntitlement()
            }
            .store(in: &cancellables)
    }
    
    func refresh() async {
        await storeKit.loadProducts()
        await storeKit.restorePurchases()
        updateEntitlement()
    }
    
    private func updateEntitlement() {
        if bypassLicenseCheck {
            entitlement = .lifetime
            isUnlocked = true
            return
        }

        if storeKit.hasLifetime {
            entitlement = .lifetime
            isUnlocked = true
            return
        }

        // Local trial logic
        let firstLaunchKey = "firstLaunchDate"
        let defaults = UserDefaults.standard

        if let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date {
            let daysSinceLaunch = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
            let daysRemaining = TrialConfig.durationDays - daysSinceLaunch

            if daysRemaining > 0 {
                entitlement = .trialActive(daysRemaining: daysRemaining)
                isUnlocked = true
                return
            } else {
                entitlement = .trialExpired
                isUnlocked = false
                return
            }
        } else {
            // First launch, record the date
            defaults.set(Date(), forKey: firstLaunchKey)
            entitlement = .trialActive(daysRemaining: TrialConfig.durationDays)
            isUnlocked = true
            return
        }
    }
    
    var statusText: String {
        #if DEBUG
        return "Debug Mode"
        #else
        switch entitlement {
        case .noTrial:
            return "No active license"
        case .trialActive(let days):
            return "Trial: \(days) day\(days == 1 ? "" : "s") remaining"
        case .trialExpired:
            return "Trial expired"
        case .lifetime:
            return "Lifetime Pro"
        }
        #endif
    }
    
    var needsPaywall: Bool {
        if bypassLicenseCheck { return false }
        
        switch entitlement {
        case .noTrial, .trialExpired:
            return true
        case .trialActive, .lifetime:
            return false
        }
    }
    
    var canStartTrial: Bool {
        false  // Local trial starts automatically, no purchase needed
    }
}
