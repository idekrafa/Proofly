import Combine
import Foundation

struct PaywallPlanOption: Equatable, Identifiable {
    let product: ProofKitSubscriptionProduct
    let package: RevenueCatPackageSnapshot?

    var id: String { product.id }
    var title: String { product.displayName }

    var subtitle: String? {
        switch product {
        case .weekly:
            nil
        case .monthly:
            String(localized: "Best value for keeping every case organized.")
        }
    }

    var creditLine: String {
        product.creditLineText
    }

    var priceText: String {
        package?.displayPrice ?? product.fallbackPrice
    }

    var renewalPriceText: String {
        let price = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !price.contains("/") else { return price }

        switch product {
        case .weekly:
            return String(localized: "\(price)/week")
        case .monthly:
            return String(localized: "\(price)/month")
        }
    }

    var trialLine: String? {
        guard product == .weekly else { return nil }

        if let duration = package?.introductoryOfferDurationText {
            return String(localized: "Start with a free trial for \(duration) and 3 AI credits. Then \(renewalPriceText) after trial.")
        }

        return String(localized: "Start with the free trial shown at checkout and 3 AI credits. Then \(renewalPriceText) after trial.")
    }

    var badgeText: String? {
        product == .monthly ? String(localized: "Best value") : nil
    }

    var accessibilityDescription: String {
        [title, renewalPriceText, creditLine, trialLine, subtitle, badgeText].compactMap { $0 }.joined(separator: ", ")
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
    let buttonTitle: String
    let action: Action

    enum Action: Equatable {
        case acknowledge
        case dismissPaywallForActiveEntitlement
    }

    init(
        title: String,
        message: String,
        buttonTitle: String = String(localized: "OK"),
        action: Action = .acknowledge
    ) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.action = action
    }

    static func == (lhs: PurchaseManagerNotice, rhs: PurchaseManagerNotice) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var offering = RevenueCatOfferingSnapshot.empty
    @Published private(set) var offeringState: PaywallOfferingState = .idle
    @Published var selectedProduct: ProofKitSubscriptionProduct = .weekly
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
                title: String(localized: "Purchases Unavailable"),
                message: String(localized: "Purchases are not ready yet. Please try again.")
            )
            return nil
        }

        guard let selectedPackage else {
            notice = PurchaseManagerNotice(
                title: String(localized: "Plans Still Loading"),
                message: String(localized: "We couldn’t load this App Store plan yet. Check your connection and try again.")
            )
            return nil
        }

        guard !isPurchasing else { return nil }
        isPurchasing = true
        defer { isPurchasing = false }

        let outcome = await subscriptions.purchase(selectedPackage)
        handlePurchase(outcome, fallbackTitle: String(localized: "Couldn’t Start Purchase"))
        return outcome
    }

    func restorePurchases() async {
        guard let subscriptions else {
            notice = PurchaseManagerNotice(
                title: String(localized: "Restore Unavailable"),
                message: String(localized: "Purchases are not ready yet. Please try again.")
            )
            return
        }

        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        let outcome = await subscriptions.restorePurchases()
        handleRestore(outcome, fallbackTitle: String(localized: "Couldn’t Restore Purchases"))
    }

    private func loadOffering() async {
        guard let subscriptions else { return }

        guard subscriptions.isConfigured else {
            offering = .empty
            offeringState = .failed(String(localized: "Purchases are not configured for this build yet. Add the RevenueCat public SDK key, then try again."))
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
                offeringState = .failed(String(localized: "We couldn’t find the weekly and monthly Pro plans in the current RevenueCat offering. Please retry after the offering is configured."))
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

    private func handlePurchase(_ outcome: RevenueCatPurchaseOutcome, fallbackTitle: String) {
        if outcome.customerInfo?.isProofKitProActive == true {
            notice = PurchaseManagerNotice(
                title: String(localized: "Welcome to Proofly Pro"),
                message: String(localized: "You’re all set. Unlimited cases, unlimited proof, clean exports, and your Pro AI credits are ready."),
                buttonTitle: String(localized: "Start Organizing"),
                action: .dismissPaywallForActiveEntitlement
            )
            return
        }

        handleInactiveOutcome(outcome, fallbackTitle: fallbackTitle)
    }

    private func handleRestore(_ outcome: RevenueCatPurchaseOutcome, fallbackTitle: String) {
        if outcome.customerInfo?.isProofKitProActive == true {
            shouldDismissForActiveEntitlement = true
            return
        }

        handleInactiveOutcome(outcome, fallbackTitle: fallbackTitle)
    }

    private func handleInactiveOutcome(_ outcome: RevenueCatPurchaseOutcome, fallbackTitle: String) {
        guard !outcome.userCancelled else { return }

        notice = PurchaseManagerNotice(
            title: outcome.isSuccessful ? String(localized: "Subscription Updated") : fallbackTitle,
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
