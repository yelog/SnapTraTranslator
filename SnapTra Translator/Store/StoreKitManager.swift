import Foundation
import StoreKit
import Combine

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var trialPurchaseDate: Date?
    @Published private(set) var isLoading = false
    
    private var updateListenerTask: Task<Void, Error>?
    
    private init() {
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    var trialProduct: Product? {
        products.first { $0.id == ProductID.trial }
    }
    
    var lifetimeProduct: Product? {
        products.first { $0.id == ProductID.lifetime }
    }
    
    var hasLifetime: Bool {
        purchasedProductIDs.contains(ProductID.lifetime)
    }
    
    var hasTrial: Bool {
        purchasedProductIDs.contains(ProductID.trial)
    }
    
    var trialDaysRemaining: Int? {
        guard let purchaseDate = trialPurchaseDate else { return nil }
        let expirationDate = Calendar.current.date(byAdding: .day, value: TrialConfig.durationDays, to: purchaseDate)!
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        return max(0, remaining)
    }
    
    var isTrialExpired: Bool {
        guard hasTrial, let remaining = trialDaysRemaining else { return false }
        return remaining <= 0
    }
    
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            products = try await Product.products(for: ProductID.all)
        } catch {
            print("[StoreKitManager] Failed to load products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
            return true
            
        case .userCancelled:
            return false
            
        case .pending:
            return false
            
        @unknown default:
            return false
        }
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            print("[StoreKitManager] Restore failed: \(error)")
        }
    }
    
    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        var trialDate: Date?
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
                
                if transaction.productID == ProductID.trial {
                    trialDate = transaction.purchaseDate
                }
            }
        }
        
        purchasedProductIDs = purchased
        trialPurchaseDate = trialDate
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self.updatePurchasedProducts()
                await transaction.finish()
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let item):
            return item
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
