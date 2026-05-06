import Foundation
import StoreKit

/// Manages subscription state using StoreKit 2.
/// Handles product loading, purchasing, restoration, and transaction verification.
@Observable @MainActor
final class SubscriptionManager {

    static let shared = SubscriptionManager()

    // MARK: - State

    var currentTier: SubscriptionTier = .free
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Private

    nonisolated(unsafe) private var transactionListener: Task<Void, Error>?

    private init() {
        // Start listening for transaction updates (renewals, revocations)
        transactionListener = listenForTransactionUpdates()

        // Check current entitlements on launch
        Task {
            await checkSubscriptionStatus()
            await loadProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    /// Fetch available subscription products from StoreKit.
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: SubscriptionProductID.all)
            // Sort: monthly first, then yearly
            products = storeProducts.sorted { p1, p2 in
                let order: [String: Int] = [
                    SubscriptionProductID.proMonthly: 0,
                    SubscriptionProductID.proYearly: 1
                ]
                return (order[p1.id] ?? 99) < (order[p2.id] ?? 99)
            }

            if products.isEmpty {
                print("[Subscription] No products found. Check StoreKit configuration.")
            } else {
                print("[Subscription] Loaded \(products.count) product(s): \(products.map(\.id))")
            }
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("[Subscription] Product load error: \(error)")
        }
    }

    // MARK: - Purchase

    /// Purchase a subscription product.
    func purchase(_ product: Product) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerification(verification)
                await transaction.finish()
                purchasedProductIDs.insert(product.id)
                updateTier()
                print("[Subscription] Purchase successful: \(product.id)")

            case .userCancelled:
                print("[Subscription] Purchase cancelled by user.")

            case .pending:
                print("[Subscription] Purchase pending (e.g., Ask to Buy).")

            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Restore Purchases

    /// Restore previously purchased subscriptions.
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Sync with App Store
        do {
            try await AppStore.sync()
        } catch {
            print("[Subscription] Sync error: \(error)")
        }

        await checkSubscriptionStatus()

        if currentTier == .pro {
            print("[Subscription] Restore successful — Pro tier active.")
        } else {
            errorMessage = "No active subscription found."
            print("[Subscription] Restore: no active subscriptions.")
        }
    }

    // MARK: - Check Status

    /// Check current subscription entitlements.
    func checkSubscriptionStatus() async {
        var activePurchases: Set<String> = []

        // Iterate through all verified transactions
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    activePurchases.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = activePurchases
        updateTier()
    }

    // MARK: - Transaction Listener

    /// Listen for real-time transaction updates (renewals, expirations, revocations).
    private func listenForTransactionUpdates() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.checkSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Verification

    /// Verify a transaction using StoreKit 2's built-in verification.
    private func checkVerification<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw SubscriptionError.verificationFailed(error.localizedDescription)
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Tier Update

    /// Update the current tier based on purchased product IDs.
    private func updateTier() {
        let hasProSubscription = !purchasedProductIDs.intersection(SubscriptionProductID.all).isEmpty
        currentTier = hasProSubscription ? .pro : .free
    }

    // MARK: - Helpers

    /// Get the monthly product.
    var monthlyProduct: Product? {
        products.first(where: { $0.id == SubscriptionProductID.proMonthly })
    }

    /// Get the yearly product.
    var yearlyProduct: Product? {
        products.first(where: { $0.id == SubscriptionProductID.proYearly })
    }

    /// Check if a specific product is purchased.
    func isProductPurchased(_ productID: String) -> Bool {
        purchasedProductIDs.contains(productID)
    }

    enum SubscriptionError: LocalizedError {
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .verificationFailed(let reason):
                return "Transaction verification failed: \(reason)"
            }
        }
    }
}
