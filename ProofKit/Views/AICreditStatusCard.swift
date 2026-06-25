import SwiftUI

struct AICreditStatusCard: View {
    @Environment(\.proofKitServices) private var services

    @State private var snapshot = AICreditStatusSnapshot.loading
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.cardSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI credits")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Local OCR is always free. AI cleanup and summaries use credits.")
                        .font(.subheadline)
                        .foregroundStyle(ProofKitVisual.helperText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    Task { await refreshStatus(force: true) }
                } label: {
                    if isRefreshing {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating")
                        }
                        .font(.footnote.weight(.semibold))
                        .transition(.opacity)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                            .transition(.opacity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh AI credit status")
            }

            VStack(spacing: 0) {
                AICreditStatusRow(
                    title: String(localized: "Current plan"),
                    value: snapshot.planName
                )

                Divider()
                    .padding(.leading, 16)

                AICreditStatusRow(
                    title: String(localized: "Credits remaining"),
                    value: snapshot.remainingCreditsText
                )

                Divider()
                    .padding(.leading, 16)

                AICreditStatusRow(
                    title: String(localized: "Renews"),
                    value: snapshot.renewalText
                )
            }
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProofKitVisual.fieldBackground)
            }

            Text(snapshot.explanation)
                .font(.caption)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)

            if let statusMessage = snapshot.statusMessage {
                Text(statusMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(ProofKitMotion.compactInsertion)
            }
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
            await refreshStatus(force: false)
        }
        .animation(ProofKitMotion.standard, value: isRefreshing)
        .animation(ProofKitMotion.standard, value: snapshot)
    }

    @MainActor
    private func refreshStatus(force: Bool) async {
        if isRefreshing { return }
        if !force, snapshot.hasLoaded { return }

        withAnimation(ProofKitMotion.standard) {
            isRefreshing = true
        }
        defer {
            withAnimation(ProofKitMotion.standard) {
                isRefreshing = false
            }
        }

        let entitlement = await services.paywall.currentEntitlement()

        guard services.account.isConfigured else {
            withAnimation(ProofKitMotion.standard) {
                snapshot = Self.fallbackSnapshot(for: entitlement)
            }
            return
        }

        do {
            let balance = try await services.aiCredits.fetchAICreditBalance()

            withAnimation(ProofKitMotion.standard) {
                snapshot = AICreditStatusSnapshot(
                    planName: entitlement.statusDisplayText,
                    remainingCreditsText: "\(balance.availableCredits)",
                    renewalText: Self.renewalText(for: entitlement, balance: balance),
                    explanation: Self.standardExplanation,
                    statusMessage: Self.statusMessage(for: balance),
                    hasLoaded: true
                )
            }
        } catch {
            withAnimation(ProofKitMotion.standard) {
                snapshot = Self.fallbackSnapshot(
                    for: entitlement,
                    statusMessage: Self.creditErrorMessage(for: error)
                )
            }
        }
    }

    private static func statusMessage(for balance: AICreditBalance) -> String? {
        if balance.availableCredits <= 0 {
            return String(localized: "AI cleanup and summaries will be available when credits renew.")
        }

        return nil
    }

    private static func creditErrorMessage(for error: Error) -> String {
        if let proofKitError = error as? ProofKitError {
            switch proofKitError {
            case .supabaseNotConfigured, .supabaseSDKUnavailable:
                return String(localized: "Credit status could not be refreshed. Showing the credits included with your current plan.")
            default:
                break
            }
        }

        return String(localized: "Credit status could not be refreshed. Showing the credits included with your current plan.")
    }

    private static func fallbackSnapshot(
        for entitlement: ProofKitEntitlementSnapshot,
        statusMessage: String? = nil
    ) -> AICreditStatusSnapshot {
        AICreditStatusSnapshot(
            planName: entitlement.statusDisplayText,
            remainingCreditsText: "\(entitlement.includedAICredits)",
            renewalText: renewalText(for: entitlement, balance: nil),
            explanation: standardExplanation,
            statusMessage: statusMessage,
            hasLoaded: true
        )
    }

    private static func renewalText(
        for entitlement: ProofKitEntitlementSnapshot,
        balance: AICreditBalance?
    ) -> String {
        if let renewsAt = balance?.renewsAt {
            return renewsAt.formatted(.dateTime.month(.abbreviated).day().year())
        }

        return entitlement.aiCreditRenewalText
    }

    private static let standardExplanation = String(localized: "AI credits are only used when you choose an AI action. Importing files, OCR, organizing your timeline, and exporting your case PDF do not use credits.")
}

private struct AICreditStatusSnapshot: Equatable {
    let planName: String
    let remainingCreditsText: String
    let renewalText: String
    let explanation: String
    let statusMessage: String?
    let hasLoaded: Bool

    static let loading = AICreditStatusSnapshot(
        planName: String(localized: "Loading…"),
        remainingCreditsText: String(localized: "Loading…"),
        renewalText: String(localized: "Monthly"),
        explanation: String(localized: "Local OCR is always free. AI cleanup and summaries use credits."),
        statusMessage: nil,
        hasLoaded: false
    )
}

private struct AICreditStatusRow: View {
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
    AICreditStatusCard()
        .padding()
        .background(Color(.systemGroupedBackground))
}
