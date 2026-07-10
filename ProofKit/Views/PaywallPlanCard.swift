import SwiftUI

struct PaywallPlanCard: View {
    let plan: PaywallPlanOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                selectionIndicator

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(plan.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ProofKitPaywallStyle.ink)

                        if let badgeText = plan.badgeText {
                            Text(badgeText)
                                .font(.caption2.weight(.bold))
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .foregroundStyle(ProofKitPaywallStyle.teal)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(ProofKitPaywallStyle.teal.opacity(0.12))
                                }
                        }
                    }

                    if let trialLine = plan.trialLine {
                        Text(trialLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ProofKitPaywallStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let subtitle = plan.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(ProofKitPaywallStyle.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                Text(plan.renewalPriceText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ProofKitPaywallStyle.ink)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .shadow(
                color: ProofKitPaywallStyle.shadow.opacity(isSelected ? 0.18 : 0.10),
                radius: isSelected ? 18 : 10,
                x: 0,
                y: isSelected ? 10 : 5
            )
        }
        .buttonStyle(ProofKitCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(plan.accessibilityDescription), \(isSelected ? String(localized: "selected") : String(localized: "not selected"))"))
        .accessibilityHint(Text("Double tap to select this plan."))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? ProofKitPaywallStyle.teal : ProofKitPaywallStyle.border, lineWidth: 2)
                .frame(width: 24, height: 24)

            if isSelected {
                Circle()
                    .fill(ProofKitPaywallStyle.teal)
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isSelected ? ProofKitPaywallStyle.selectedCard : ProofKitPaywallStyle.card)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(isSelected ? ProofKitPaywallStyle.teal : ProofKitPaywallStyle.border, lineWidth: isSelected ? 1.6 : 1)
    }
}

struct PaywallLimitsCard: View {
    @Environment(\.proofKitServices) private var services

    @State private var entitlement = ProofKitEntitlementSnapshot.placeholder()

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.cardSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan limits")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(entitlement.statusDisplayText)
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
                PlanLimitRow(title: String(localized: "Cases"), value: entitlement.limits.activeCaseLimitText)
                Divider()
                    .padding(.leading, 14)
                PlanLimitRow(title: String(localized: "Evidence"), value: entitlement.limits.evidenceItemLimitText)
                Divider()
                    .padding(.leading, 14)
                PlanLimitRow(title: String(localized: "Export"), value: entitlement.limits.exportLimitText)
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProofKitVisual.fieldBackground)
            }

            Text(entitlement.source == .revenueCat ? String(localized: "RevenueCat checks the Pro entitlement. Local cases, proof files, OCR text, and exports remain stored in Proofly’s account-scoped local storage.") : String(localized: "Purchases are placeholder-backed for now. RevenueCat can replace this entitlement source without changing local proof storage."))
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

#Preview("Plan option") {
    PaywallPlanCard(
        plan: PaywallPlanOption(product: .monthly, package: nil),
        isSelected: true,
        action: {}
    )
    .padding()
    .background(ProofKitPaywallStyle.background)
}

#Preview("Plan limits") {
    PaywallLimitsCard()
        .padding()
        .background(Color(.systemGroupedBackground))
}
