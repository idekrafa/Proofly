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
                title: "Case limit reached",
                message: "\(entitlement.plan.displayName) includes \(entitlement.limits.activeCaseLimitText). Archive an old case or upgrade to Pro for unlimited cases.",
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
                message = "\(entitlement.plan.displayName) includes \(entitlement.limits.evidenceItemLimitText). Upgrade to Paid Urgent Export or Pro to add more proof."
            } else {
                message = "You can add \(remainingCount) more proof item\(remainingCount == 1 ? "" : "s") on \(entitlement.plan.displayName). Select fewer files or upgrade for a higher limit."
            }

            return PaywallAccessDecision(
                isAllowed: false,
                title: "Evidence limit reached",
                message: message,
                suggestedPlan: entitlement.plan == .free ? .paidUrgentExport : .pro
            )
        }

        return .allowed
    }

    func canUseAI() async -> PaywallAccessDecision {
        let entitlement = await currentEntitlement()
        guard entitlement.limits.monthlyAICredits > 0 else {
            return PaywallAccessDecision(
                isAllowed: false,
                title: "AI credits unavailable",
                message: "\(entitlement.plan.displayName) does not include AI credits. OCR and local organization still work.",
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
                blockedTitle: "Final export already used",
                blockedMessage: "\(entitlement.plan.displayName) includes \(entitlement.limits.exportLimitText). Upgrade to Pro for additional non-watermarked exports."
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
