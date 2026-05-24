import SwiftUI
import UIKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.proofKitServices) private var services

    @StateObject private var purchaseManager = PurchaseManager()
    @State private var didDismissForEntitlement = false
    @State private var didTrackPaywallViewed = false

    let onPurchaseCompleted: () async -> Void

    init(onPurchaseCompleted: @escaping () async -> Void = {}) {
        self.onPurchaseCompleted = onPurchaseCompleted
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ProofKitPaywallStyle.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    heroSection
                    benefitCard
                    offeringStatus
                    planSelector
                }
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 58)
                .padding(.bottom, 10)
            }

            closeButton
                .padding(.top, 14)
                .padding(.trailing, 18)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
        .tint(ProofKitPaywallStyle.teal)
        .task {
            trackPaywallViewedIfNeeded()
            await purchaseManager.load(using: services.subscriptions)
        }
        .onChange(of: purchaseManager.shouldDismissForActiveEntitlement) { _, shouldDismiss in
            guard shouldDismiss, !didDismissForEntitlement else { return }
            didDismissForEntitlement = true
            Task { @MainActor in
                await onPurchaseCompleted()
                dismiss()
            }
        }
        .alert(item: $purchaseManager.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func trackPaywallViewedIfNeeded() {
        guard !didTrackPaywallViewed else { return }
        didTrackPaywallViewed = true
        services.analytics.trackPaywallViewed(sourceScreen: .settings)
    }

    @MainActor
    private func purchaseSelectedPlan() async {
        services.analytics.trackSubscriptionStarted(sourceScreen: .paywall)
        guard let outcome = await purchaseManager.purchaseSelectedPlan() else {
            services.analytics.trackSubscriptionFailed(sourceScreen: .paywall, errorType: .subscriptionFailed)
            return
        }

        if outcome.customerInfo?.isProofKitProActive == true {
            services.analytics.trackSubscriptionCompleted(sourceScreen: .paywall)
        } else if !outcome.userCancelled {
            services.analytics.trackSubscriptionFailed(sourceScreen: .paywall, errorType: .subscriptionFailed)
        }
    }

    private var closeButton: some View {
        Button {
            services.analytics.trackPaywallDismissed(sourceScreen: .settings)
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ProofKitPaywallStyle.ink)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(ProofKitPaywallStyle.card.opacity(0.95))
                        .shadow(color: ProofKitPaywallStyle.shadow.opacity(0.12), radius: 10, x: 0, y: 5)
                }
        }
        .buttonStyle(ProofKitCardButtonStyle())
        .accessibilityLabel("Close paywall")
    }

    private var heroSection: some View {
        VStack(alignment: .center, spacing: 18) {
            Image("rook_image")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 240)
                .frame(maxWidth: .infinity, alignment: .center)
                .shadow(color: ProofKitPaywallStyle.shadow.opacity(0.16), radius: 18, x: 0, y: 12)
                .accessibilityLabel("Rook holding an organized proof packet")

            VStack(spacing: 10) {
                Text("Your proof, organized.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(ProofKitPaywallStyle.ink)
                    .kerning(-0.8)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
                    .lineLimit(2)

                Text("Start your free trial")
                    .font(.body.weight(.medium))
                    .foregroundStyle(ProofKitPaywallStyle.mutedInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var benefitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaywallBenefitRow(text: "Organize screenshots, photos, notes, and documents")
            PaywallBenefitRow(text: "Turn messy proof into a clear timeline")
            PaywallBenefitRow(text: "Full Pro access during trial, including unlimited cases, unlimited proof, clean exports, and 3 AI credits")
            PaywallBenefitRow(text: "Weekly Pro includes 15 AI credits/week")
            PaywallBenefitRow(text: "Monthly Pro includes 75 AI credits/month")
            PaywallBenefitRow(text: "Cancel anytime before the trial ends")
            PaywallBenefitRow(text: "Raw files stay on your device")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ProofKitPaywallStyle.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(ProofKitPaywallStyle.border, lineWidth: 1)
        }
        .shadow(color: ProofKitPaywallStyle.shadow.opacity(0.10), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private var offeringStatus: some View {
        switch purchaseManager.offeringState {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading secure App Store prices…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ProofKitPaywallStyle.mutedInk)
            }
            .paywallStatusCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading App Store prices")
        case .loaded:
            EmptyView()
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Plans need a quick refresh", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProofKitPaywallStyle.ink)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(ProofKitPaywallStyle.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await purchaseManager.retryLoadingOffering() }
                } label: {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Retry loading plans")
            }
            .paywallStatusCard()
        }
    }

    private var planSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your Pro plan")
                .font(.headline.weight(.bold))
                .foregroundStyle(ProofKitPaywallStyle.ink)

            VStack(spacing: 12) {
                ForEach(purchaseManager.plans) { plan in
                    PaywallPlanCard(
                        plan: plan,
                        isSelected: purchaseManager.selectedProduct == plan.product
                    ) {
                        withAnimation(ProofKitMotion.standard) {
                            purchaseManager.select(plan.product)
                        }
                    }
                }
            }
        }
    }

    private var bottomActionBar: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchaseSelectedPlan() }
            } label: {
                HStack(spacing: 10) {
                    if purchaseManager.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(purchaseButtonTitle)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(purchaseManager.canPurchaseSelectedPlan ? ProofKitPaywallStyle.teal : ProofKitPaywallStyle.teal.opacity(0.45))
                }
            }
            .buttonStyle(ProofKitCardButtonStyle())
            .disabled(!purchaseManager.canPurchaseSelectedPlan)
            .accessibilityLabel(purchaseButtonTitle)

            Text(billingDisclosureText)
                .font(.caption.weight(.medium))
                .foregroundStyle(ProofKitPaywallStyle.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Link("Terms", destination: ProofKitPaywallLinks.termsURL)
                    .accessibilityLabel("Terms")

                Circle()
                    .fill(ProofKitPaywallStyle.border)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)

                Link("Privacy", destination: ProofKitPaywallLinks.privacyURL)
                    .accessibilityLabel("Privacy")

                Circle()
                    .fill(ProofKitPaywallStyle.border)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)

                Button {
                    Task { await purchaseManager.restorePurchases() }
                } label: {
                    if purchaseManager.isRestoring {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Restoring")
                        }
                    } else {
                        Text("Restore purchases")
                    }
                }
                .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
                .accessibilityLabel("Restore purchases")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ProofKitPaywallStyle.teal)
            .lineLimit(1)
            .minimumScaleFactor(0.78)

            Text("Cancel anytime before the trial ends to avoid being charged. Proofly is an organization tool, not legal advice.")
                .font(.caption2)
                .foregroundStyle(ProofKitPaywallStyle.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(ProofKitPaywallStyle.background.opacity(0.96))
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ProofKitPaywallStyle.border)
                        .frame(height: 1)
                }
        }
    }

    private var selectedPlanOption: PaywallPlanOption {
        PaywallPlanOption(
            product: purchaseManager.selectedProduct,
            package: purchaseManager.selectedPackage
        )
    }

    private var purchaseButtonTitle: String {
        if purchaseManager.isPurchasing {
            return "Starting…"
        }

        switch purchaseManager.selectedProduct {
        case .weekly:
            return "Start free trial"
        case .monthly:
            return "Continue with Monthly Pro"
        }
    }

    private var billingDisclosureText: String {
        let selectedPlan = selectedPlanOption

        switch selectedPlan.product {
        case .weekly:
            let trialText = selectedPlan.package?.introductoryOfferDurationText.map {
                "Your free trial lasts \($0)."
            } ?? "The App Store checkout shows your exact free-trial length."

            return "\(trialText) Then \(selectedPlan.renewalPriceText) after trial. Trial includes full Pro access and 3 AI credits. Weekly Pro includes 15 AI credits/week."
        case .monthly:
            return "Monthly Pro is \(selectedPlan.renewalPriceText) and includes 75 AI credits/month."
        }
    }
}

enum ProofKitPaywallStyle {
    static let background = Color(UIColor(red: 0.985, green: 0.965, blue: 0.925, alpha: 1.0))
    static let card = Color(UIColor(red: 1.0, green: 0.992, blue: 0.972, alpha: 1.0))
    static let selectedCard = Color(UIColor(red: 0.938, green: 0.988, blue: 0.970, alpha: 1.0))
    static let ink = Color(UIColor(red: 0.075, green: 0.105, blue: 0.145, alpha: 1.0))
    static let mutedInk = Color(UIColor(red: 0.31, green: 0.37, blue: 0.42, alpha: 1.0))
    static let teal = Color(UIColor(red: 0.04, green: 0.55, blue: 0.53, alpha: 1.0))
    static let border = Color(UIColor(red: 0.12, green: 0.18, blue: 0.20, alpha: 0.10))
    static let shadow = Color(UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0))
}

enum ProofKitPaywallLinks {
    static let termsURL = URL(string: "https://proofly.app/terms")!
    static let privacyURL = URL(string: "https://proofly.app/privacy")!
}

private extension View {
    func paywallStatusCard() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ProofKitPaywallStyle.card.opacity(0.84))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ProofKitPaywallStyle.border, lineWidth: 1)
            }
    }
}

#Preview {
    PaywallView()
}
