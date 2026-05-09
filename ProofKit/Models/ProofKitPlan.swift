import Foundation

enum ProofKitPlan: String, CaseIterable, Codable, Identifiable {
    case free
    case paidUrgentExport
    case pro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free:
            "Free"
        case .paidUrgentExport:
            "Paid urgent export"
        case .pro:
            "Pro"
        }
    }

    var limits: ProofKitPlanLimits {
        switch self {
        case .free:
            ProofKitPlanLimits(
                activeCaseLimit: 1,
                evidenceItemLimit: 20,
                monthlyAICredits: 5,
                aiCreditsRenewMonthly: true,
                finalCaseExportLimit: nil,
                exportsAreWatermarked: true
            )
        case .paidUrgentExport:
            ProofKitPlanLimits(
                activeCaseLimit: 1,
                evidenceItemLimit: 75,
                monthlyAICredits: 25,
                aiCreditsRenewMonthly: false,
                finalCaseExportLimit: 1,
                exportsAreWatermarked: false
            )
        case .pro:
            ProofKitPlanLimits(
                activeCaseLimit: nil,
                evidenceItemLimit: nil,
                monthlyAICredits: 100,
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
        activeCaseLimit.map { "\($0) active case\($0 == 1 ? "" : "s")" } ?? "Unlimited active cases"
    }

    var evidenceItemLimitText: String {
        evidenceItemLimit.map { "\($0) proof items" } ?? "Unlimited proof items"
    }

    var aiCreditLimitText: String {
        "\(monthlyAICredits) AI credit\(monthlyAICredits == 1 ? "" : "s")\(aiCreditsRenewMonthly ? "/month" : "")"
    }

    var exportLimitText: String {
        if let finalCaseExportLimit {
            return "\(finalCaseExportLimit) final case export\(finalCaseExportLimit == 1 ? "" : "s")"
        }

        return exportsAreWatermarked ? "Watermarked PDF exports" : "Non-watermarked exports"
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
            "Placeholder"
        case .placeholderOverride:
            "Placeholder override"
        case .purchaseEntitlement:
            "Purchase entitlement"
        case .revenueCat:
            "RevenueCat"
        }
    }
}

struct ProofKitEntitlementSnapshot: Equatable {
    let plan: ProofKitPlan
    let source: ProofKitEntitlementSource
    let updatedAt: Date

    var limits: ProofKitPlanLimits { plan.limits }
    var includedAICredits: Int { limits.monthlyAICredits }

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
            title: blockedTitle ?? "Export limit reached",
            message: blockedMessage ?? "This plan has reached its export limit.",
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
