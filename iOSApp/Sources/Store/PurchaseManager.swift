import Foundation
import StoreKit

// Product ID for the one-time premium unlock
private let kPremiumProductId = "com.maclauncher.ios.premium"

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    private init() {}

    @Published var product: Product?
    @Published var isLoading = false
    @Published var purchaseError: String?

    // MARK: - Transaction Observer

    func startTransactionObserver() {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let tx) = result,
                      tx.productID == kPremiumProductId else { continue }
                AppState.shared.unlockPremium()
                await tx.finish()
            }
        }
    }

    // MARK: - Lifecycle

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [kPremiumProductId])
            product = products.first
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                AppState.shared.unlockPremium()
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await checkExistingEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Check Entitlements on Launch

    func checkExistingEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == kPremiumProductId {
                AppState.shared.unlockPremium()
                return
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    var formattedPrice: String {
        product?.displayPrice ?? "$6.99"
    }
}
