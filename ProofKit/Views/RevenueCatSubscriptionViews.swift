import SwiftUI

#if canImport(RevenueCatUI)
import RevenueCatUI
#endif

struct RevenueCatSubscriptionManagementCard: View {
    @Environment(\.proofKitServices) private var services

    let onEntitlementChanged: (ProofKitEntitlementSnapshot) -> Void

    @State private var offering = RevenueCatOfferingSnapshot.empty
    @State private var isLoadingOffering = false
    @State private var purchasingPackageID: RevenueCatPackageSnapshot.ID?
    @State private var isRestoring = false
    @State private var notice: RevenueCatSubscriptionNotice?
    @State private var showingCustomPaywall = false
    @State private var showingCustomerCenter = false

    private var canUseRevenueCat: Bool {
        services.subscriptions.isConfigured
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProofKitVisual.cardSpacing) {
            header

            if canUseRevenueCat {
                if services.subscriptions.isUsingRevenueCatTestKey {
                    Label("Using a RevenueCat test SDK key. Replace it with your production public SDK key before App Store release.", systemImage: "testtube.2")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                primaryActions

                if isLoadingOffering {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading RevenueCat offering…")
                            .font(.subheadline)
                            .foregroundStyle(ProofKitVisual.helperText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    packageList
                }
            } else {
                Text("Add the RevenueCat API key to local or CI build settings to enable subscriptions for this build.")
                    .font(.subheadline)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .fixedSize(horizontal: false, vertical: true)
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
            await loadOffering()
        }
        .sheet(isPresented: $showingCustomPaywall) {
            PaywallView {
                await refreshEntitlementAfterRevenueCatChange()
            }
        }
        .sheet(isPresented: $showingCustomerCenter) {
            ProofKitRevenueCatCustomerCenterSheet(
                onCustomerInfoChanged: {
                    await refreshEntitlementAfterRevenueCatChange()
                },
                onError: { error in
                    notice = RevenueCatSubscriptionNotice(
                        title: String(localized: "Customer Center Error"),
                        message: Self.message(for: error)
                    )
                }
            )
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Proofly Pro")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(ProofKitSubscriptionConstants.proEntitlementIdentifier)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProofKitVisual.helperText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        Capsule(style: .continuous)
                            .fill(ProofKitVisual.quietFill)
                    }
            }

            Text("RevenueCat unlocks Pro from the configured entitlement. Weekly and monthly packages should map to the configured App Store product IDs.")
                .font(.caption)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryActions: some View {
        VStack(spacing: 10) {
            Button {
                showingCustomPaywall = true
            } label: {
                Label("Open Proofly Paywall", systemImage: "crown.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 10) {
                Button {
                    Task { await restorePurchases() }
                } label: {
                    if isRestoring {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Restore", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRestoring)

                Button {
                    showingCustomerCenter = true
                } label: {
                    Label("Manage", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var packageList: some View {
        if offering.availablePackages.isEmpty {
            Text("No weekly/monthly packages were returned. In RevenueCat, make a current Offering with Weekly and Monthly packages, and attach both products to the Pro entitlement.")
                .font(.subheadline)
                .foregroundStyle(ProofKitVisual.helperText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                ForEach(offering.availablePackages) { package in
                    RevenueCatPackageRow(
                        package: package,
                        isPurchasing: purchasingPackageID == package.id
                    ) {
                        Task { await purchase(package) }
                    }
                }
            }
        }
    }

    @MainActor
    private func loadOffering() async {
        guard canUseRevenueCat else { return }
        isLoadingOffering = true
        defer { isLoadingOffering = false }

        do {
            offering = try await services.subscriptions.currentOffering()
        } catch {
            notice = RevenueCatSubscriptionNotice(
                title: String(localized: "Couldn’t Load Plans"),
                message: Self.message(for: error)
            )
        }
    }

    @MainActor
    private func purchase(_ package: RevenueCatPackageSnapshot) async {
        guard purchasingPackageID == nil else { return }
        purchasingPackageID = package.id
        defer { purchasingPackageID = nil }

        services.analytics.trackSubscriptionStarted(sourceScreen: .settings)
        let outcome = await services.subscriptions.purchase(package)
        if outcome.customerInfo?.isProofKitProActive == true {
            services.analytics.trackSubscriptionCompleted(sourceScreen: .settings)
        } else if !outcome.userCancelled {
            services.analytics.trackSubscriptionFailed(sourceScreen: .settings, errorType: .subscriptionFailed)
        }
        await handle(outcome)
    }

    @MainActor
    private func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        let outcome = await services.subscriptions.restorePurchases()
        await handle(outcome)
    }

    @MainActor
    private func handle(_ outcome: RevenueCatPurchaseOutcome) async {
        if let snapshot = outcome.customerInfo {
            onEntitlementChanged(snapshot.entitlementSnapshot)
        }

        if !outcome.userCancelled {
            notice = RevenueCatSubscriptionNotice(
                title: outcome.isSuccessful ? String(localized: "Subscription Updated") : String(localized: "Subscription Notice"),
                message: outcome.message
            )
        }
    }

    @MainActor
    private func refreshEntitlementAfterRevenueCatChange() async {
        do {
            let snapshot = try await services.subscriptions.refreshCustomerInfo()
            onEntitlementChanged(snapshot.entitlementSnapshot)
        } catch {
            notice = RevenueCatSubscriptionNotice(
                title: String(localized: "Couldn’t Refresh Subscription"),
                message: Self.message(for: error)
            )
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

private struct RevenueCatPackageRow: View {
    let package: RevenueCatPackageSnapshot
    let isPurchasing: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(package.product.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(package.title)
                    .font(.caption)
                    .foregroundStyle(ProofKitVisual.helperText)
                    .lineLimit(2)

                if let introductoryPrice = package.localizedIntroductoryPrice {
                    Text("Intro offer: \(introductoryPrice)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 12)

            Button {
                action()
            } label: {
                if isPurchasing {
                    ProgressView()
                        .frame(minWidth: 72)
                } else {
                    Text(package.displayPrice)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 72)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isPurchasing)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProofKitVisual.fieldBackground)
        }
    }
}

private struct ProofKitRevenueCatCustomerCenterSheet: View {
    let onCustomerInfoChanged: () async -> Void
    let onError: (Error) -> Void

    var body: some View {
        #if canImport(RevenueCatUI)
        CustomerCenterView()
            .onCustomerCenterRestoreCompleted { _ in
                Task { await onCustomerInfoChanged() }
            }
            .onCustomerCenterRestoreFailed { error in
                onError(error)
            }
        #else
        UnavailableRevenueCatUIView()
        #endif
    }
}

private struct UnavailableRevenueCatUIView: View {
    var body: some View {
        ContentUnavailableView(
            "RevenueCat UI Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("Add the RevenueCatUI Swift Package product to present paywalls and Customer Center.")
        )
    }
}

private struct RevenueCatSubscriptionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
