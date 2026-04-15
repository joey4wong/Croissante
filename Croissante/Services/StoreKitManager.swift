import Combine
import Foundation
import StoreKit
import WidgetKit

@MainActor
final class StoreKitManager: ObservableObject {
    enum MemberProduct: String, CaseIterable, Identifiable {
        case monthly
        case yearly
        case lifetime

        var id: String { rawValue }

        // Keep these identifiers aligned with the products configured in App Store Connect.
        var productID: String {
            switch self {
            case .monthly:
                return "com.jw.croissante.plus.monthly"
            case .yearly:
                return "com.jw.croissante.plus.yearly"
            case .lifetime:
                return "com.jw.croissante.plus.lifetime"
            }
        }

        init?(productID: String) {
            switch productID {
            case Self.monthly.productID:
                self = .monthly
            case Self.yearly.productID:
                self = .yearly
            case Self.lifetime.productID:
                self = .lifetime
            default:
                return nil
            }
        }

        var priority: Int {
            switch self {
            case .monthly:
                return 1
            case .yearly:
                return 2
            case .lifetime:
                return 3
            }
        }
    }

    enum PurchaseOutcome {
        case success
        case pending
        case cancelled
        case failed(String)
    }

    enum RestoreOutcome {
        case restored
        case nothingToRestore
        case failed(String)
    }

    @Published private(set) var productsByPlan: [MemberProduct: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPerformingStoreAction = false
    @Published private(set) var memberUnlocked = false
    @Published private(set) var purchasedProduct: MemberProduct?

    private let appState: AppState
    private var transactionUpdatesTask: Task<Void, Never>?
    private var storefrontUpdatesTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
        transactionUpdatesTask = observeTransactionUpdates()
        storefrontUpdatesTask = observeStorefrontUpdates()

        Task {
            await syncMembershipStatus()
            await refreshProductsForCurrentStorefront()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
        storefrontUpdatesTask?.cancel()
    }

    func product(for plan: MemberProduct) -> Product? {
        productsByPlan[plan]
    }

    func loadProductsIfNeeded(force: Bool = false) async {
        if !force && (!productsByPlan.isEmpty || isLoadingProducts) {
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetchedProducts = try await Product.products(for: MemberProduct.allCases.map(\.productID))
            productsByPlan = Dictionary(
                uniqueKeysWithValues: fetchedProducts.compactMap { product in
                    guard let plan = MemberProduct(productID: product.id) else { return nil }
                    return (plan, product)
                }
            )
        } catch {
            // Leave any previously loaded products in place if the App Store request fails.
        }
    }

    func refreshProductsForCurrentStorefront() async {
        await loadProductsIfNeeded(force: true)
    }

    func syncMembershipStatus() async {
        var highestEntitlement: MemberProduct?
        var highestEntitlementExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }
            guard let plan = MemberProduct(productID: transaction.productID) else { continue }

            if let current = highestEntitlement {
                if plan.priority > current.priority {
                    highestEntitlement = plan
                    highestEntitlementExpirationDate = transaction.expirationDate
                }
            } else {
                highestEntitlement = plan
                highestEntitlementExpirationDate = transaction.expirationDate
            }
        }

        let resolvedMemberUnlocked = highestEntitlement != nil
        let membershipChanged = memberUnlocked != resolvedMemberUnlocked
        let widgetDefaultsChanged = WidgetDataService.writeMemberAccess(
            resolvedMemberUnlocked,
            expirationDate: highestEntitlementExpirationDate,
            neverExpires: highestEntitlement == .lifetime
        )

        purchasedProduct = highestEntitlement
        memberUnlocked = resolvedMemberUnlocked
        if appState.memberUnlocked != resolvedMemberUnlocked {
            appState.memberUnlocked = resolvedMemberUnlocked
        }
        if membershipChanged || widgetDefaultsChanged {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func purchase(_ plan: MemberProduct) async -> PurchaseOutcome {
        await loadProductsIfNeeded()

        guard let product = productsByPlan[plan] else {
            return .failed("Membership product unavailable. Verify the product identifiers in App Store Connect.")
        }

        isPerformingStoreAction = true
        defer { isPerformingStoreAction = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                await transaction.finish()
                await syncMembershipStatus()
                return .success
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("The App Store returned an unknown purchase result.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> RestoreOutcome {
        isPerformingStoreAction = true
        defer { isPerformingStoreAction = false }

        do {
            try await AppStore.sync()
            await syncMembershipStatus()
            return memberUnlocked ? .restored : .nothingToRestore
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }

                do {
                    let transaction = try self.verifiedTransaction(from: result)
                    await self.syncMembershipStatus()
                    await transaction.finish()
                } catch {
                    continue
                }
            }
        }
    }

    private func observeStorefrontUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await _ in Storefront.updates {
                guard let self else { break }
                await self.refreshProductsForCurrentStorefront()
            }
        }
    }

    private func verifiedTransaction(from result: VerificationResult<StoreKit.Transaction>) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }
}
