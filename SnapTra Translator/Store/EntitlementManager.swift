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
            .combineLatest(storeKit.$trialPurchaseDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
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
        
        if storeKit.hasTrial {
            if let daysRemaining = storeKit.trialDaysRemaining, daysRemaining > 0 {
                entitlement = .trialActive(daysRemaining: daysRemaining)
                isUnlocked = true
            } else {
                entitlement = .trialExpired
                isUnlocked = false
            }
            return
        }
        
        entitlement = .noTrial
        isUnlocked = false
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
        entitlement == .noTrial
    }
}
