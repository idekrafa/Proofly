import Foundation

#if canImport(RevenueCat)
import RevenueCat
#endif

enum ProofKitSubscriptionConstants {
    static let revenueCatAPIKeyInfoPlistKey = "PROOFKIT_REVENUECAT_API_KEY"
    static let proEntitlementIdentifier = "pro"
    static let alternateProEntitlementIdentifier = "proofkit_pro"
    static let legacyProEntitlementIdentifier = "ProofKit Pro"
    static let proEntitlementIdentifiers = [
        proEntitlementIdentifier,
        alternateProEntitlementIdentifier,
        legacyProEntitlementIdentifier
    ]
    static let weeklyProductIdentifier = "proofkit_pro_weekly"
    static let monthlyProductIdentifier = "proofkit_pro_monthly"
}

struct RevenueCatConfiguration: Equatable {
    let apiKey: String

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isTestKey: Bool {
        apiKey.hasPrefix("test_")
    }

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RevenueCatConfiguration? {
        guard let apiKey = firstNonEmptyString(
            keys: [
                ProofKitSubscriptionConstants.revenueCatAPIKeyInfoPlistKey,
                "REVENUECAT_API_KEY"
            ],
            bundle: bundle,
            environment: environment
        ) else {
            return nil
        }

        return RevenueCatConfiguration(apiKey: apiKey)
    }

    private static func firstNonEmptyString(
        keys: [String],
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        for key in keys {
            if let value = environment[key]?.proofKitRevenueCatConfigurationValue {
                return value
            }

            if let value = bundle.object(forInfoDictionaryKey: key) as? String,
               let cleaned = value.proofKitRevenueCatConfigurationValue {
                return cleaned
            }
        }

        return nil
    }
}

enum ProofKitSubscriptionProduct: String, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly:
            "Weekly Pro"
        case .monthly:
            "Monthly Pro"
        }
    }

    var cadenceLabel: String {
        switch self {
        case .weekly:
            "Weekly"
        case .monthly:
            "Monthly"
        }
    }

    var fallbackPrice: String {
        switch self {
        case .weekly:
            "$3.99"
        case .monthly:
            "$9.99"
        }
    }

    var configuredProductIdentifier: String {
        switch self {
        case .weekly:
            ProofKitSubscriptionConstants.weeklyProductIdentifier
        case .monthly:
            ProofKitSubscriptionConstants.monthlyProductIdentifier
        }
    }

    var fallbackPackageIdentifiers: [String] {
        switch self {
        case .weekly:
            [configuredProductIdentifier, "weekly", "$rc_weekly"]
        case .monthly:
            [configuredProductIdentifier, "monthly", "$rc_monthly"]
        }
    }
}

struct RevenueCatCustomerInfoSnapshot: Equatable {
    let appUserID: String
    let originalAppUserID: String
    let activeEntitlementIDs: [String]
    let activeProductIDs: [String]
    let activeSubscriptionProduct: ProofKitSubscriptionProduct?
    let subscriptionStatus: ProofKitSubscriptionStatus
    let managementURL: URL?
    let latestExpirationDate: Date?
    let isProofKitProActive: Bool
    let updatedAt: Date

    var entitlementSnapshot: ProofKitEntitlementSnapshot {
        ProofKitEntitlementSnapshot(
            plan: isProofKitProActive ? .pro : .free,
            source: .revenueCat,
            updatedAt: updatedAt,
            subscriptionProduct: activeSubscriptionProduct,
            subscriptionStatus: subscriptionStatus
        )
    }
}

struct RevenueCatPackageSnapshot: Equatable, Identifiable {
    let id: String
    let product: ProofKitSubscriptionProduct
    let packageIdentifier: String
    let productIdentifier: String
    let title: String
    let subtitle: String
    let localizedPrice: String
    let localizedIntroductoryPrice: String?
    let introductoryOfferDurationText: String?

    var displayPrice: String {
        let trimmedPrice = localizedPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrice.isEmpty ? product.fallbackPrice : trimmedPrice
    }
}

struct RevenueCatOfferingSnapshot: Equatable {
    let offeringIdentifier: String?
    let hasRevenueCatPaywall: Bool
    let weekly: RevenueCatPackageSnapshot?
    let monthly: RevenueCatPackageSnapshot?
    let availablePackages: [RevenueCatPackageSnapshot]

    static let empty = RevenueCatOfferingSnapshot(
        offeringIdentifier: nil,
        hasRevenueCatPaywall: false,
        weekly: nil,
        monthly: nil,
        availablePackages: []
    )
}

struct RevenueCatPurchaseOutcome: Equatable {
    let customerInfo: RevenueCatCustomerInfoSnapshot?
    let userCancelled: Bool
    let message: String

    var isSuccessful: Bool {
        customerInfo != nil && !userCancelled
    }
}

@MainActor
protocol SubscriptionServicing {
    var isConfigured: Bool { get }
    var isUsingRevenueCatTestKey: Bool { get }

    func configure()
    func identifyCustomer(for session: ProofKitAccountSession) async
    func resetCustomerForSignedOutState() async
    func currentEntitlementSnapshot() async throws -> ProofKitEntitlementSnapshot
    func refreshCustomerInfo() async throws -> RevenueCatCustomerInfoSnapshot
    func currentOffering() async throws -> RevenueCatOfferingSnapshot
    func purchase(_ package: RevenueCatPackageSnapshot) async -> RevenueCatPurchaseOutcome
    func restorePurchases() async -> RevenueCatPurchaseOutcome
}

@MainActor
final class RevenueCatSubscriptionService: SubscriptionServicing {
    private let configuration: RevenueCatConfiguration?
    private var didConfigure = false
    private var customerInfoUpdatesTask: Task<Void, Never>?
    private var latestCustomerInfoSnapshot: RevenueCatCustomerInfoSnapshot?

    var isConfigured: Bool {
        #if canImport(RevenueCat)
        configuration?.isConfigured == true
        #else
        false
        #endif
    }

    var isUsingRevenueCatTestKey: Bool {
        configuration?.isTestKey == true
    }

    static func live() -> RevenueCatSubscriptionService {
        RevenueCatSubscriptionService(configuration: .load())
    }

    init(configuration: RevenueCatConfiguration?) {
        self.configuration = configuration
    }

    deinit {
        customerInfoUpdatesTask?.cancel()
    }

    func configure() {
        #if canImport(RevenueCat)
        guard let configuration, configuration.isConfigured else { return }
        guard !didConfigure else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif

        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: configuration.apiKey)
        }

        didConfigure = true
        startCustomerInfoUpdates()
        #endif
    }

    func identifyCustomer(for session: ProofKitAccountSession) async {
        #if canImport(RevenueCat)
        configure()
        guard Purchases.isConfigured else { return }

        let appUserID = session.userID.uuidString

        do {
            let customerInfo: CustomerInfo
            if Purchases.shared.appUserID == appUserID {
                customerInfo = try await Purchases.shared.customerInfo()
            } else {
                let loginResult = try await Purchases.shared.logIn(appUserID)
                customerInfo = loginResult.customerInfo
            }

            updateCustomerInfoSnapshot(from: customerInfo)
        } catch {
            // RevenueCat identity failures should not block access to local data.
            // The next purchase, restore, or customer-info refresh can retry.
        }
        #endif
    }

    func resetCustomerForSignedOutState() async {
        #if canImport(RevenueCat)
        configure()
        guard Purchases.isConfigured, !Purchases.shared.isAnonymous else { return }

        do {
            let customerInfo = try await Purchases.shared.logOut()
            updateCustomerInfoSnapshot(from: customerInfo)
        } catch {
            // Ignore logOutAnonymousUserError and transient network errors. ProofKit
            // sign-out must never affect local SwiftData/account-scoped files.
        }
        #endif
    }

    func currentEntitlementSnapshot() async throws -> ProofKitEntitlementSnapshot {
        do {
            return try await refreshCustomerInfo().entitlementSnapshot
        } catch {
            if let latestCustomerInfoSnapshot {
                return latestCustomerInfoSnapshot.entitlementSnapshot
            }

            throw error
        }
    }

    func refreshCustomerInfo() async throws -> RevenueCatCustomerInfoSnapshot {
        #if canImport(RevenueCat)
        configure()
        guard Purchases.isConfigured else {
            throw ProofKitError.revenueCatNotConfigured
        }

        let customerInfo = try await Purchases.shared.customerInfo()
        return updateCustomerInfoSnapshot(from: customerInfo)
        #else
        throw ProofKitError.revenueCatSDKUnavailable
        #endif
    }

    func currentOffering() async throws -> RevenueCatOfferingSnapshot {
        #if canImport(RevenueCat)
        configure()
        guard Purchases.isConfigured else {
            throw ProofKitError.revenueCatNotConfigured
        }

        let offerings = try await Purchases.shared.offerings()
        guard let currentOffering = offerings.current else {
            return .empty
        }

        return Self.snapshot(from: currentOffering)
        #else
        throw ProofKitError.revenueCatSDKUnavailable
        #endif
    }

    func purchase(_ package: RevenueCatPackageSnapshot) async -> RevenueCatPurchaseOutcome {
        #if canImport(RevenueCat)
        do {
            configure()
            guard Purchases.isConfigured else {
                throw ProofKitError.revenueCatNotConfigured
            }

            let package = try await revenueCatPackage(matching: package)
            let result = try await Purchases.shared.purchase(package: package)
            let snapshot = updateCustomerInfoSnapshot(from: result.customerInfo)

            if result.userCancelled {
                return RevenueCatPurchaseOutcome(
                    customerInfo: snapshot,
                    userCancelled: true,
                    message: "Purchase cancelled."
                )
            }

            return RevenueCatPurchaseOutcome(
                customerInfo: snapshot,
                userCancelled: false,
                message: snapshot.isProofKitProActive
                ? "Proofly Pro is active."
                : "Purchase completed, but Pro is not active yet. Check that the product is attached to the configured Pro entitlement in RevenueCat."
            )
        } catch {
            return RevenueCatPurchaseOutcome(
                customerInfo: latestCustomerInfoSnapshot,
                userCancelled: Self.isUserCancelled(error),
                message: Self.userMessage(for: error)
            )
        }
        #else
        return RevenueCatPurchaseOutcome(
            customerInfo: nil,
            userCancelled: false,
            message: ProofKitError.revenueCatSDKUnavailable.errorDescription ?? "RevenueCat SDK is unavailable in this build."
        )
        #endif
    }

    func restorePurchases() async -> RevenueCatPurchaseOutcome {
        #if canImport(RevenueCat)
        do {
            configure()
            guard Purchases.isConfigured else {
                throw ProofKitError.revenueCatNotConfigured
            }

            let customerInfo = try await Purchases.shared.restorePurchases()
            let snapshot = updateCustomerInfoSnapshot(from: customerInfo)

            return RevenueCatPurchaseOutcome(
                customerInfo: snapshot,
                userCancelled: false,
                message: snapshot.isProofKitProActive
                ? "Purchases restored. Proofly Pro is active."
                : "Restore finished, but no active Pro entitlement was found for this App Store account."
            )
        } catch {
            return RevenueCatPurchaseOutcome(
                customerInfo: latestCustomerInfoSnapshot,
                userCancelled: Self.isUserCancelled(error),
                message: Self.userMessage(for: error)
            )
        }
        #else
        return RevenueCatPurchaseOutcome(
            customerInfo: nil,
            userCancelled: false,
            message: ProofKitError.revenueCatSDKUnavailable.errorDescription ?? "RevenueCat SDK is unavailable in this build."
        )
        #endif
    }

    #if canImport(RevenueCat)
    @discardableResult
    private func updateCustomerInfoSnapshot(from customerInfo: CustomerInfo) -> RevenueCatCustomerInfoSnapshot {
        let activeEntitlementIDs = customerInfo.entitlements.active.keys.sorted()
        let normalizedActiveEntitlementIDs = Set(activeEntitlementIDs.map { $0.lowercased() })
        let isProofKitProActive = ProofKitSubscriptionConstants.proEntitlementIdentifiers.contains { identifier in
            normalizedActiveEntitlementIDs.contains(identifier.lowercased())
        }
        let proofKitEntitlement = customerInfo.entitlements.active.values.first { entitlement in
            ProofKitSubscriptionConstants.proEntitlementIdentifiers.contains { identifier in
                entitlement.identifier.lowercased() == identifier.lowercased()
            }
        }
        let activeProductIDs = customerInfo.activeSubscriptions.sorted()
        let activeSubscriptionProduct = Self.subscriptionProduct(
            activeProductIDs: activeProductIDs,
            entitlementProductID: proofKitEntitlement?.productIdentifier
        )
        let subscriptionStatus = Self.subscriptionStatus(
            isActive: isProofKitProActive,
            product: activeSubscriptionProduct,
            periodType: proofKitEntitlement?.periodType
        )

        let snapshot = RevenueCatCustomerInfoSnapshot(
            appUserID: Purchases.shared.appUserID,
            originalAppUserID: customerInfo.originalAppUserId,
            activeEntitlementIDs: activeEntitlementIDs,
            activeProductIDs: activeProductIDs,
            activeSubscriptionProduct: activeSubscriptionProduct,
            subscriptionStatus: subscriptionStatus,
            managementURL: customerInfo.managementURL,
            latestExpirationDate: customerInfo.latestExpirationDate,
            isProofKitProActive: isProofKitProActive,
            updatedAt: .now
        )

        latestCustomerInfoSnapshot = snapshot
        return snapshot
    }

    private func startCustomerInfoUpdates() {
        guard customerInfoUpdatesTask == nil else { return }

        customerInfoUpdatesTask = Task { [weak self] in
            for await customerInfo in Purchases.shared.customerInfoStream {
                guard let self else { return }
                _ = await MainActor.run {
                    self.updateCustomerInfoSnapshot(from: customerInfo)
                }
            }
        }
    }

    private func revenueCatPackage(matching snapshot: RevenueCatPackageSnapshot) async throws -> Package {
        let offerings = try await Purchases.shared.offerings()
        let allOfferings = offerings.all.values

        if let package = allOfferings
            .flatMap(\.availablePackages)
            .first(where: { package in
                package.identifier == snapshot.packageIdentifier &&
                    package.storeProduct.productIdentifier == snapshot.productIdentifier
            }) {
            return package
        }

        if let package = allOfferings
            .flatMap(\.availablePackages)
            .first(where: { $0.storeProduct.productIdentifier == snapshot.productIdentifier }) {
            return package
        }

        throw ProofKitError.revenueCatOfferingUnavailable(
            "Could not find the \(snapshot.product.displayName.lowercased()) package in the current RevenueCat offerings."
        )
    }

    private static func snapshot(from offering: Offering) -> RevenueCatOfferingSnapshot {
        let weeklyPackage = package(for: .weekly, in: offering)
        let monthlyPackage = package(for: .monthly, in: offering)
        let packages = [weeklyPackage, monthlyPackage].compactMap { $0 }

        return RevenueCatOfferingSnapshot(
            offeringIdentifier: offering.identifier,
            hasRevenueCatPaywall: offering.hasPaywall,
            weekly: weeklyPackage,
            monthly: monthlyPackage,
            availablePackages: packages
        )
    }

    private static func package(
        for product: ProofKitSubscriptionProduct,
        in offering: Offering
    ) -> RevenueCatPackageSnapshot? {
        let package: Package?

        switch product {
        case .weekly:
            package = offering.weekly ?? fallbackPackage(for: product, in: offering)
        case .monthly:
            package = offering.monthly ?? fallbackPackage(for: product, in: offering)
        }

        guard let package else { return nil }

        let storeProduct = package.storeProduct
        return RevenueCatPackageSnapshot(
            id: "\(offering.identifier)-\(package.identifier)-\(storeProduct.productIdentifier)",
            product: product,
            packageIdentifier: package.identifier,
            productIdentifier: storeProduct.productIdentifier,
            title: storeProduct.localizedTitle.isEmpty ? product.displayName : storeProduct.localizedTitle,
            subtitle: storeProduct.localizedDescription.isEmpty ? "Unlock Proofly Pro" : storeProduct.localizedDescription,
            localizedPrice: package.localizedPriceString,
            localizedIntroductoryPrice: package.localizedIntroductoryPriceString,
            introductoryOfferDurationText: storeProduct.introductoryDiscount?.subscriptionPeriod.proofKitDisplayText
        )
    }

    private static func fallbackPackage(
        for product: ProofKitSubscriptionProduct,
        in offering: Offering
    ) -> Package? {
        offering.availablePackages.first { package in
            let packageIdentifier = package.identifier.lowercased()
            let productIdentifier = package.storeProduct.productIdentifier.lowercased()
            return product.fallbackPackageIdentifiers.contains(packageIdentifier) ||
                productIdentifier == product.configuredProductIdentifier ||
                packageIdentifier.contains(product.rawValue) ||
                productIdentifier.contains(product.rawValue)
        }
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        (error as NSError).asErrorCode == .purchaseCancelledError
    }

    private static func userMessage(for error: Error) -> String {
        if let revenueCatError = (error as NSError).asErrorCode {
            switch revenueCatError {
            case .purchaseCancelledError:
                return "Purchase cancelled."
            case .networkError, .offlineConnectionError:
                return "Couldn’t reach RevenueCat. Check your connection and try again."
            case .productNotAvailableForPurchaseError:
                return "This subscription product is not available for purchase yet. Check App Store Connect and RevenueCat product configuration."
            case .purchaseNotAllowedError:
                return "Purchases are not allowed on this device."
            case .invalidCredentialsError, .configurationError:
                return "RevenueCat is not configured correctly for this build."
            default:
                return (error as NSError).localizedDescription
            }
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }

    private static func subscriptionProduct(
        activeProductIDs: [String],
        entitlementProductID: String?
    ) -> ProofKitSubscriptionProduct? {
        let productIDs = (activeProductIDs + [entitlementProductID].compactMap { $0 }).map { $0.lowercased() }

        if productIDs.contains(where: { productID in
            productID == ProofKitSubscriptionConstants.monthlyProductIdentifier ||
                productID.contains("monthly") ||
                productID.contains("month")
        }) {
            return .monthly
        }

        if productIDs.contains(where: { productID in
            productID == ProofKitSubscriptionConstants.weeklyProductIdentifier ||
                productID.contains("weekly") ||
                productID.contains("week")
        }) {
            return .weekly
        }

        return nil
    }

    private static func subscriptionStatus(
        isActive: Bool,
        product: ProofKitSubscriptionProduct?,
        periodType: PeriodType?
    ) -> ProofKitSubscriptionStatus {
        guard isActive else { return .expired }

        if periodType == .trial {
            return .trialing
        }

        switch product {
        case .weekly:
            return .activeWeekly
        case .monthly, .none:
            return .activeMonthly
        }
    }
    #endif
}

private extension String {
    var proofKitRevenueCatConfigurationValue: String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              !cleaned.contains("$("),
              !cleaned.hasPrefix("<") else {
            return nil
        }

        return cleaned
    }
}

#if canImport(RevenueCat)
private extension SubscriptionPeriod {
    var proofKitDisplayText: String {
        let unitName: String
        switch unit {
        case .day:
            unitName = value == 1 ? "day" : "days"
        case .week:
            unitName = value == 1 ? "week" : "weeks"
        case .month:
            unitName = value == 1 ? "month" : "months"
        case .year:
            unitName = value == 1 ? "year" : "years"
        @unknown default:
            unitName = "periods"
        }

        return "\(value) \(unitName)"
    }
}
#endif
