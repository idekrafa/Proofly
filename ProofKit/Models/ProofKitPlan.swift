import Foundation

enum ProofKitPlan: String, CaseIterable, Codable, Identifiable {
    case free
    case paidUrgentExport
    case pro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free:
            String(localized: "No active Pro")
        case .paidUrgentExport:
            String(localized: "Paid urgent export")
        case .pro:
            String(localized: "Pro")
        }
    }

    var limits: ProofKitPlanLimits {
        switch self {
        case .free:
            ProofKitPlanLimits(
                activeCaseLimit: 1,
                evidenceItemLimit: 20,
                monthlyAICredits: 0,
                aiCreditsRenewMonthly: true,
                finalCaseExportLimit: nil,
                exportsAreWatermarked: true
            )
        case .paidUrgentExport:
            ProofKitPlanLimits(
                activeCaseLimit: 1,
                evidenceItemLimit: 75,
                monthlyAICredits: 0,
                aiCreditsRenewMonthly: false,
                finalCaseExportLimit: 1,
                exportsAreWatermarked: false
            )
        case .pro:
            ProofKitPlanLimits(
                activeCaseLimit: nil,
                evidenceItemLimit: nil,
                monthlyAICredits: 75,
                aiCreditsRenewMonthly: true,
                finalCaseExportLimit: nil,
                exportsAreWatermarked: false
            )
        }
    }

    static func resolved(from entitlements: [PurchaseEntitlementRecord]) -> ProofKitPlan {
        let activeEntitlements = entitlements.filter { record in
            record.isActive && (record.expiresAt == nil || record.expiresAt.map { $0 > .now } == true)
        }

        if activeEntitlements.contains(where: { record in
            let value = "\(record.productID) \(record.entitlement)".lowercased()
            return value.contains("pro") || value.contains("premium")
        }) {
            return .pro
        }

        if activeEntitlements.contains(where: { record in
            let value = "\(record.productID) \(record.entitlement)".lowercased()
            return value.contains("urgent") ||
                value.contains("final") ||
                value.contains("packet") ||
                value.contains("export")
        }) {
            return .paidUrgentExport
        }

        return .free
    }

    static func placeholderOverride() -> ProofKitPlan? {
        let environmentValue = ProcessInfo.processInfo.environment["PROOFKIT_PLACEHOLDER_PLAN"]
        let defaultsValue = UserDefaults.standard.string(forKey: "proofkit.placeholderPlan")
        guard let rawValue = (environmentValue ?? defaultsValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !rawValue.isEmpty else {
            return nil
        }

        switch rawValue {
        case "free":
            return .free
        case "urgent", "urgentexport", "paidurgentexport", "paid_urgent_export", "paid-urgent-export":
            return .paidUrgentExport
        case "pro", "premium":
            return .pro
        default:
            return ProofKitPlan(rawValue: rawValue)
        }
    }
}

struct ProofKitPlanLimits: Codable, Equatable {
    let activeCaseLimit: Int?
    let evidenceItemLimit: Int?
    let monthlyAICredits: Int
    let aiCreditsRenewMonthly: Bool
    let finalCaseExportLimit: Int?
    let exportsAreWatermarked: Bool

    var activeCaseLimitText: String {
        activeCaseLimit.map { count in
            count == 1
                ? String(localized: "\(count) active case")
                : String(localized: "\(count) active cases")
        } ?? String(localized: "Unlimited active cases")
    }

    var evidenceItemLimitText: String {
        evidenceItemLimit.map { String(localized: "\($0) proof items") } ?? String(localized: "Unlimited proof items")
    }

    var aiCreditLimitText: String {
        guard monthlyAICredits > 0 else { return String(localized: "No AI credits") }
        if aiCreditsRenewMonthly {
            return monthlyAICredits == 1
                ? String(localized: "\(monthlyAICredits) AI credit/month")
                : String(localized: "\(monthlyAICredits) AI credits/month")
        }
        return monthlyAICredits == 1
            ? String(localized: "\(monthlyAICredits) AI credit")
            : String(localized: "\(monthlyAICredits) AI credits")
    }

    var exportLimitText: String {
        if let finalCaseExportLimit {
            return finalCaseExportLimit == 1
                ? String(localized: "\(finalCaseExportLimit) final case export")
                : String(localized: "\(finalCaseExportLimit) final case exports")
        }

        return exportsAreWatermarked ? String(localized: "Watermarked PDF exports") : String(localized: "Non-watermarked exports")
    }
}

enum ProofKitEntitlementSource: String, Codable {
    case placeholder
    case placeholderOverride
    case purchaseEntitlement
    case revenueCat

    var displayName: String {
        switch self {
        case .placeholder:
            String(localized: "Placeholder")
        case .placeholderOverride:
            String(localized: "Placeholder override")
        case .purchaseEntitlement:
            String(localized: "Purchase entitlement")
        case .revenueCat:
            "RevenueCat"
        }
    }
}

enum ProofKitSubscriptionStatus: String, Codable, Equatable {
    case trialing
    case activeWeekly = "active_weekly"
    case activeMonthly = "active_monthly"
    case expired
    case cancelled
    case billingRetry = "billing_retry"
    case revokedOrRefunded = "revoked_or_refunded"

    var displayName: String {
        switch self {
        case .trialing:
            String(localized: "Trial")
        case .activeWeekly:
            String(localized: "Weekly Pro")
        case .activeMonthly:
            String(localized: "Monthly Pro")
        case .expired:
            String(localized: "Expired")
        case .cancelled:
            String(localized: "Cancelled")
        case .billingRetry:
            String(localized: "Billing retry")
        case .revokedOrRefunded:
            String(localized: "Revoked or refunded")
        }
    }

    var allowsAI: Bool {
        switch self {
        case .trialing, .activeWeekly, .activeMonthly:
            true
        case .expired, .cancelled, .billingRetry, .revokedOrRefunded:
            false
        }
    }
}

struct ProofKitEntitlementSnapshot: Equatable {
    let plan: ProofKitPlan
    let source: ProofKitEntitlementSource
    let updatedAt: Date
    let subscriptionProduct: ProofKitSubscriptionProduct?
    let subscriptionStatus: ProofKitSubscriptionStatus

    var limits: ProofKitPlanLimits { plan.limits }
    var includedAICredits: Int {
        guard subscriptionStatus.allowsAI || plan == .pro else { return 0 }
        if subscriptionStatus == .trialing { return ProofKitTrialPolicy.aiCreditAllowance }
        return subscriptionProduct?.includedAICredits ?? limits.monthlyAICredits
    }

    var aiCreditRenewalText: String {
        if subscriptionStatus == .trialing {
            return String(localized: "Trial, then weekly")
        }

        if let subscriptionProduct {
            return subscriptionProduct.creditRenewalText
        }

        return limits.aiCreditsRenewMonthly ? String(localized: "Monthly") : String(localized: "One-time")
    }

    var statusDisplayText: String {
        if plan == .pro {
            return subscriptionStatus.displayName
        }

        return plan.displayName
    }

    init(
        plan: ProofKitPlan,
        source: ProofKitEntitlementSource,
        updatedAt: Date,
        subscriptionProduct: ProofKitSubscriptionProduct? = nil,
        subscriptionStatus: ProofKitSubscriptionStatus? = nil
    ) {
        self.plan = plan
        self.source = source
        self.updatedAt = updatedAt
        self.subscriptionProduct = subscriptionProduct
        self.subscriptionStatus = subscriptionStatus ?? (plan == .pro ? .activeMonthly : .expired)
    }

    static func placeholder(_ plan: ProofKitPlan = .free) -> ProofKitEntitlementSnapshot {
        ProofKitEntitlementSnapshot(
            plan: plan,
            source: .placeholder,
            updatedAt: .now
        )
    }
}

struct PaywallAccessDecision: Equatable, Identifiable {
    let isAllowed: Bool
    let title: String
    let message: String
    let suggestedPlan: ProofKitPlan?

    var id: String {
        "\(isAllowed)-\(title)-\(message)-\(suggestedPlan?.rawValue ?? "none")"
    }

    static let allowed = PaywallAccessDecision(
        isAllowed: true,
        title: "",
        message: "",
        suggestedPlan: nil
    )
}

extension ProofKitSubscriptionProduct {
    var includedAICredits: Int {
        switch self {
        case .weekly:
            15
        case .monthly:
            75
        }
    }

    var creditRenewalText: String {
        switch self {
        case .weekly:
            String(localized: "Weekly")
        case .monthly:
            String(localized: "Monthly")
        }
    }

    var creditLineText: String {
        switch self {
        case .weekly:
            String(localized: "15 AI credits/week")
        case .monthly:
            String(localized: "75 AI credits/month")
        }
    }
}

enum ProofKitTrialPolicy {
    static let aiCreditAllowance = 3
}

struct ProofKitExportAccess: Equatable {
    let isAllowed: Bool
    let plan: ProofKitPlan
    let isWatermarked: Bool
    let exportedCaseCount: Int
    let limit: Int?
    let blockedTitle: String?
    let blockedMessage: String?

    var blockedDecision: PaywallAccessDecision? {
        guard !isAllowed else { return nil }
        return PaywallAccessDecision(
            isAllowed: false,
            title: blockedTitle ?? String(localized: "Export limit reached"),
            message: blockedMessage ?? String(localized: "This plan has reached its export limit."),
            suggestedPlan: .pro
        )
    }

    static let placeholderFree = ProofKitExportAccess(
        isAllowed: true,
        plan: .free,
        isWatermarked: true,
        exportedCaseCount: 0,
        limit: nil,
        blockedTitle: nil,
        blockedMessage: nil
    )
}
