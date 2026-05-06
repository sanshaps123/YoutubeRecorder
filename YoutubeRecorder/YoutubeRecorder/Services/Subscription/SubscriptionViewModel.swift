import Foundation
import StoreKit

/// ViewModel for the PaywallView.
/// Wraps SubscriptionManager with purchase-specific UI state.
@Observable @MainActor
final class SubscriptionViewModel {

    // MARK: - State

    var isLoading = false
    var isPurchasing = false
    var errorMessage: String?
    var showSuccessAlert = false

    // MARK: - Dependencies

    private let subscriptionManager = SubscriptionManager.shared

    // MARK: - Computed Properties

    var products: [Product] { subscriptionManager.products }
    var currentTier: SubscriptionTier { subscriptionManager.currentTier }
    var monthlyProduct: Product? { subscriptionManager.monthlyProduct }
    var yearlyProduct: Product? { subscriptionManager.yearlyProduct }
    var isPro: Bool { currentTier == .pro }

    /// Computed savings percentage for yearly vs monthly.
    var yearlySavingsPercent: Int? {
        guard let monthly = monthlyProduct,
              let yearly = yearlyProduct else { return nil }
        let monthlyAnnual = monthly.price * 12
        guard monthlyAnnual > 0 else { return nil }
        let savings = ((monthlyAnnual - yearly.price) / monthlyAnnual) * 100
        return Int((savings as NSDecimalNumber).doubleValue.rounded())
    }

    // MARK: - Actions

    /// Load products from StoreKit.
    func loadProducts() async {
        isLoading = true
        await subscriptionManager.loadProducts()
        isLoading = false
    }

    /// Purchase a subscription product.
    func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil

        do {
            try await subscriptionManager.purchase(product)
            if subscriptionManager.currentTier == .pro {
                showSuccessAlert = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isPurchasing = false
    }

    /// Restore previous purchases.
    func restore() async {
        isLoading = true
        errorMessage = nil
        await subscriptionManager.restorePurchases()
        if subscriptionManager.currentTier == .pro {
            showSuccessAlert = true
        } else {
            errorMessage = subscriptionManager.errorMessage
        }
        isLoading = false
    }
}
