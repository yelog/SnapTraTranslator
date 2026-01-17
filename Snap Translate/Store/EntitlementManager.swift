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
    
    private init() {
        setupBindings()
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
    }
    
    var needsPaywall: Bool {
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
