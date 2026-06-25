import Foundation

@MainActor
protocol PaywallServicing {
    func currentEntitlement() async -> ProofKitEntitlementSnapshot
    func canCreateCase(existingCases: [CaseFile]) async -> PaywallAccessDecision
    func canAddEvidence(to caseFile: CaseFile, adding additionalItemCount: Int) async -> PaywallAccessDecision
    func canUseAI() async -> PaywallAccessDecision
    func exportAccess(for caseFile: CaseFile) async -> ProofKitExportAccess
}

@MainActor
final class PlaceholderPaywallService: PaywallServicing {
    private let purchaseEntitlements: any PurchaseEntitlementServicing
    private let subscriptions: any SubscriptionServicing

    init(
        purchaseEntitlements: any PurchaseEntitlementServicing,
        subscriptions: any SubscriptionServicing
    ) {
        self.purchaseEntitlements = purchaseEntitlements
        self.subscriptions = subscriptions
    }

    func currentEntitlement() async -> ProofKitEntitlementSnapshot {
        if let override = ProofKitPlan.placeholderOverride() {
            return ProofKitEntitlementSnapshot(
                plan: override,
                source: .placeholderOverride,
                updatedAt: .now
            )
        }

        if subscriptions.isConfigured {
            do {
                return try await subscriptions.currentEntitlementSnapshot()
            } catch {
                // Keep ProofKit usable if RevenueCat is temporarily unavailable.
                // The Supabase entitlement fallback below is non-destructive and
                // does not touch local SwiftData or file storage.
            }
        }

        do {
            let entitlements = try await purchaseEntitlements.fetchPurchaseEntitlements()
            return ProofKitEntitlementSnapshot(
                plan: ProofKitPlan.resolved(from: entitlements),
                source: .purchaseEntitlement,
                updatedAt: .now
            )
        } catch {
            return .placeholder(.free)
        }
    }

    func canCreateCase(existingCases: [CaseFile]) async -> PaywallAccessDecision {
        let entitlement = await currentEntitlement()
        guard let activeCaseLimit = entitlement.limits.activeCaseLimit else {
            return .allowed
        }

        let activeCaseCount = existingCases.filter(\.countsTowardActiveCaseLimit).count
        guard activeCaseCount < activeCaseLimit else {
            return PaywallAccessDecision(
                isAllowed: false,
                title: String(localized: "Case limit reached"),
                message: String(localized: "\(entitlement.statusDisplayText) includes \(entitlement.limits.activeCaseLimitText). Start Pro for unlimited cases."),
                suggestedPlan: .pro
            )
        }

        return .allowed
    }

    func canAddEvidence(to caseFile: CaseFile, adding additionalItemCount: Int) async -> PaywallAccessDecision {
        let entitlement = await currentEntitlement()
        guard let evidenceItemLimit = entitlement.limits.evidenceItemLimit else {
            return .allowed
        }

        let requestedCount = max(additionalItemCount, 1)
        let currentCount = caseFile.evidenceItems.count
        let remainingCount = max(0, evidenceItemLimit - currentCount)

        guard currentCount + requestedCount <= evidenceItemLimit else {
            let message: String
            if remainingCount == 0 {
                message = String(localized: "\(entitlement.statusDisplayText) includes \(entitlement.limits.evidenceItemLimitText). Start Pro to add more proof.")
            } else {
                message = String(localized: "You can add \(remainingCount) more proof item\(remainingCount == 1 ? "" : "s") on \(entitlement.statusDisplayText). Select fewer files or start Pro for a higher limit.")
            }

            return PaywallAccessDecision(
                isAllowed: false,
                title: String(localized: "Evidence limit reached"),
                message: message,
                suggestedPlan: .pro
            )
        }

        return .allowed
    }

    func canUseAI() async -> PaywallAccessDecision {
        let entitlement = await currentEntitlement()
        guard entitlement.includedAICredits > 0, entitlement.subscriptionStatus.allowsAI || entitlement.plan == .pro else {
            return PaywallAccessDecision(
                isAllowed: false,
                title: String(localized: "AI credits unavailable"),
                message: String(localized: "\(entitlement.statusDisplayText) does not include available AI credits. Local OCR and organization still work."),
                suggestedPlan: .pro
            )
        }

        return .allowed
    }

    func exportAccess(for caseFile: CaseFile) async -> ProofKitExportAccess {
        let entitlement = await currentEntitlement()
        let exportedCaseCount = caseFile.exportPackets.count
        let exportLimit = entitlement.limits.finalCaseExportLimit

        if let exportLimit, exportedCaseCount >= exportLimit {
            return ProofKitExportAccess(
                isAllowed: false,
                plan: entitlement.plan,
                isWatermarked: entitlement.limits.exportsAreWatermarked,
                exportedCaseCount: exportedCaseCount,
                limit: exportLimit,
                blockedTitle: String(localized: "Final export already used"),
                blockedMessage: String(localized: "\(entitlement.statusDisplayText) includes \(entitlement.limits.exportLimitText). Start Pro for additional non-watermarked exports.")
            )
        }

        return ProofKitExportAccess(
            isAllowed: true,
            plan: entitlement.plan,
            isWatermarked: entitlement.limits.exportsAreWatermarked,
            exportedCaseCount: exportedCaseCount,
            limit: exportLimit,
            blockedTitle: nil,
            blockedMessage: nil
        )
    }
}

extension CaseFile {
    var countsTowardActiveCaseLimit: Bool {
        archivedAt == nil && status != .archived
    }
}
