import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var storeKit = StoreKitManager.shared
    @ObservedObject private var entitlement = EntitlementManager.shared
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    featuresSection
                    
                    purchaseSection
                    
                    restoreSection
                }
                .padding(24)
            }
        }
        .frame(width: 400, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            Text("Snap Translate Pro")
                .font(.system(size: 20, weight: .bold))
            
            Text("Translate any text on screen instantly")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    @ViewBuilder
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureRow(icon: "text.magnifyingglass", title: "OCR Translation", description: "Point and translate any text on screen")
            FeatureRow(icon: "speaker.wave.2", title: "Pronunciation", description: "Hear the correct pronunciation")
            FeatureRow(icon: "book.closed", title: "Dictionary", description: "View detailed definitions and examples")
            FeatureRow(icon: "globe", title: "14+ Languages", description: "Support for major world languages")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    @ViewBuilder
    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if entitlement.canStartTrial, let trialProduct = storeKit.trialProduct {
                PurchaseButton(
                    title: "Start 30-Day Free Trial",
                    subtitle: "Full access, no commitment",
                    isPrimary: true,
                    isLoading: isPurchasing
                ) {
                    await purchase(trialProduct)
                }
            }
            
            if let lifetimeProduct = storeKit.lifetimeProduct {
                PurchaseButton(
                    title: "Lifetime Pro — \(lifetimeProduct.displayPrice)",
                    subtitle: "One-time purchase, forever access",
                    isPrimary: !entitlement.canStartTrial,
                    isLoading: isPurchasing
                ) {
                    await purchase(lifetimeProduct)
                }
            }
            
            // App Store required disclosure
            disclosureText
            
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }
    
    @ViewBuilder
    private var disclosureText: some View {
        VStack(spacing: 4) {
            if entitlement.canStartTrial {
                Text("Free for 30 days. After the trial ends, translation features will be locked until you purchase Lifetime Pro.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Your trial has ended. Purchase Lifetime Pro to unlock all features.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var restoreSection: some View {
        Button("Restore Purchases") {
            Task {
                await storeKit.restorePurchases()
                if !entitlement.needsPaywall {
                    dismiss()
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    
    private func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        
        do {
            let success = try await storeKit.purchase(product)
            if success && !entitlement.needsPaywall {
                dismiss()
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
        }
        
        isPurchasing = false
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct PurchaseButton: View {
    let title: String
    let subtitle: String
    let isPrimary: Bool
    let isLoading: Bool
    let action: () async -> Void
    
    var body: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            HStack {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .opacity(0.8)
                }
                
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isPrimary ? Color.blue : Color(nsColor: .controlBackgroundColor))
            )
            .foregroundStyle(isPrimary ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

#Preview {
    PaywallView()
}
