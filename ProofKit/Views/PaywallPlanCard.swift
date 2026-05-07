import SwiftUI

struct PaywallPlanCard: View {
    @Environment(\.proofKitServices) private var services

    @State private var entitlement = ProofKitEntitlementSnapshot.placeholder()

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.cardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan limits")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(entitlement.plan.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ProofKitVisual.helperText)
                }

                Spacer(minLength: 12)

                Text(entitlement.source.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(ProofKitVisual.quietFill)
                    }
            }

            VStack(spacing: 0) {
                PlanLimitRow(title: "Cases", value: entitlement.limits.activeCaseLimitText)
                Divider()
                    .padding(.leading, 14)
                PlanLimitRow(title: "Evidence", value: entitlement.limits.evidenceItemLimitText)
                Divider()
                    .padding(.leading, 14)
                PlanLimitRow(title: "AI credits", value: entitlement.limits.aiCreditLimitText)
                Divider()
                    .padding(.leading, 14)
                PlanLimitRow(title: "Export", value: entitlement.limits.exportLimitText)
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProofKitVisual.fieldBackground)
            }

            Text("Purchases are placeholder-backed for now. StoreKit or RevenueCat can replace this entitlement source later without changing local evidence storage.")
                .font(.caption)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ProofKitVisual.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                .fill(ProofKitVisual.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ProofKitVisual.panelCornerRadius, style: .continuous)
                .stroke(ProofKitVisual.cardBorder, lineWidth: 1)
        }
        .task {
            entitlement = await services.paywall.currentEntitlement()
        }
    }
}

private struct PlanLimitRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}

#Preview {
    PaywallPlanCard()
        .padding()
        .background(Color(.systemGroupedBackground))
}
