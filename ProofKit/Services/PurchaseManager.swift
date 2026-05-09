import Combine
import Foundation

struct PaywallPlanOption: Equatable, Identifiable {
    let product: ProofKitSubscriptionProduct
    let package: RevenueCatPackageSnapshot?

    var id: String { product.id }
    var title: String { product.displayName }

    var subtitle: String {
        switch product {
        case .weekly:
            "Flexible access for short sprints."
        case .monthly:
            "Best for keeping every case organized."
        }
    }

    var creditLine: String {
        switch product {
        case .weekly:
            "15 AI credits / week"
        case .monthly:
            "75 AI credits / month"
        }
    }

    var priceText: String {
        package?.displayPrice ?? product.fallbackPrice
    }

    var badgeText: String? {
        product == .monthly ? "Best value" : nil
    }

    var accessibilityDescription: String {
        [title, priceText, creditLine, subtitle, badgeText].compactMap { $0 }.joined(separator: ", ")
    }
}

enum PaywallOfferingState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct PurchaseManagerNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: PurchaseManagerNotice, rhs: PurchaseManagerNotice) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var offering = RevenueCatOfferingSnapshot.empty
    @Published private(set) var offeringState: PaywallOfferingState = .idle
    @Published var selectedProduct: ProofKitSubscriptionProduct = .monthly
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var notice: PurchaseManagerNotice?
    @Published private(set) var shouldDismissForActiveEntitlement = false

    private var subscriptions: (any SubscriptionServicing)?

    var plans: [PaywallPlanOption] {
        ProofKitSubscriptionProduct.allCases.map { product in
            PaywallPlanOption(product: product, package: package(for: product))
        }
    }

    var selectedPackage: RevenueCatPackageSnapshot? {
        package(for: selectedProduct)
    }

    var canPurchaseSelectedPlan: Bool {
        selectedPackage != nil && !offeringState.isLoading && !isPurchasing && !isRestoring
    }

    var isBusy: Bool {
        offeringState.isLoading || isPurchasing || isRestoring
    }

    func load(using subscriptions: any SubscriptionServicing) async {
        self.subscriptions = subscriptions
        await refreshActiveEntitlement()
        guard !shouldDismissForActiveEntitlement else { return }
        await loadOffering()
    }

    func retryLoadingOffering() async {
        await loadOffering()
    }

    func select(_ product: ProofKitSubscriptionProduct) {
        selectedProduct = product
    }

    @discardableResult
    func purchaseSelectedPlan() async -> RevenueCatPurchaseOutcome? {
        guard let subscriptions else {
            notice = PurchaseManagerNotice(
                title: "Purchases Unavailable",
                message: "Purchases are not ready yet. Please try again."
            )
            return nil
        }

        guard let selectedPackage else {
            notice = PurchaseManagerNotice(
                title: "Plans Still Loading",
                message: "We couldn’t load this App Store plan yet. Check your connection and try again."
            )
            return nil
        }

        guard !isPurchasing else { return nil }
        isPurchasing = true
        defer { isPurchasing = false }

        let outcome = await subscriptions.purchase(selectedPackage)
        handle(outcome, fallbackTitle: "Couldn’t Start Purchase")
        return outcome
    }

    func restorePurchases() async {
        guard let subscriptions else {
            notice = PurchaseManagerNotice(
                title: "Restore Unavailable",
                message: "Purchases are not ready yet. Please try again."
            )
            return
        }

        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        let outcome = await subscriptions.restorePurchases()
        handle(outcome, fallbackTitle: "Couldn’t Restore Purchases")
    }

    private func loadOffering() async {
        guard let subscriptions else { return }

        guard subscriptions.isConfigured else {
            offering = .empty
            offeringState = .failed("Purchases are not configured for this build yet. Add the RevenueCat public SDK key, then try again.")
            return
        }

        offeringState = .loading

        do {
            let loadedOffering = try await subscriptions.currentOffering()
            offering = loadedOffering

            if loadedOffering.monthly != nil {
                selectedProduct = .monthly
            } else if loadedOffering.weekly != nil {
                selectedProduct = .weekly
            } else {
                selectedProduct = .monthly
            }

            if loadedOffering.availablePackages.isEmpty {
                offeringState = .failed("We couldn’t find the weekly and monthly Pro plans in the current RevenueCat offering. Please retry after the offering is configured.")
            } else {
                offeringState = .loaded
            }
        } catch {
            offering = .empty
            offeringState = .failed(Self.userMessage(for: error))
        }
    }

    private func refreshActiveEntitlement() async {
        guard let subscriptions, subscriptions.isConfigured else { return }

        do {
            let customerInfo = try await subscriptions.refreshCustomerInfo()
            if customerInfo.isProofKitProActive {
                shouldDismissForActiveEntitlement = true
            }
        } catch {
            // Offering load below presents a retry path. Existing local data access must
            // not depend on a RevenueCat refresh succeeding.
        }
    }

    private func package(for product: ProofKitSubscriptionProduct) -> RevenueCatPackageSnapshot? {
        switch product {
        case .weekly:
            offering.weekly
        case .monthly:
            offering.monthly
        }
    }

    private func handle(_ outcome: RevenueCatPurchaseOutcome, fallbackTitle: String) {
        if outcome.customerInfo?.isProofKitProActive == true {
            shouldDismissForActiveEntitlement = true
            return
        }

        guard !outcome.userCancelled else { return }

        notice = PurchaseManagerNotice(
            title: outcome.isSuccessful ? "Subscription Updated" : fallbackTitle,
            message: outcome.message
        )
    }

    private static func userMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
