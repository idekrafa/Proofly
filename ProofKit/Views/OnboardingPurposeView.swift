import SwiftUI

enum ProofKitPendingOnboardingSeedStore {
    private static let seedIDKey = "proofkit.pendingOnboardingFirstCaseSeedID"
    private static let seedSavedAtKey = "proofkit.pendingOnboardingFirstCaseSeedSavedAt"
    private static let profileDisplayNameKey = "proofkit.pendingOnboardingProfileDisplayName"
    private static let accountCreationAttemptedAtKey = "proofkit.pendingOnboardingAccountCreationAttemptedAt"
    private static let accountCreationEmailKey = "proofkit.pendingOnboardingAccountCreationEmail"
    private static let accountCreationAttemptMaxAge: TimeInterval = 7 * 24 * 60 * 60

    static func save(_ seed: ProofKitOnboardingFirstCaseSeed) {
        UserDefaults.standard.set(seed.id, forKey: seedIDKey)
        UserDefaults.standard.set(Date(), forKey: seedSavedAtKey)
        UserDefaults.standard.synchronize()
    }

    static func pendingSeed() -> ProofKitOnboardingFirstCaseSeed? {
        guard let seedID = UserDefaults.standard.string(forKey: seedIDKey) else {
            return nil
        }

        return CaseCategory.firstCaseSeed(for: seedID)
    }

    static func saveProfileDisplayName(_ displayName: String?) {
        guard let normalizedName = ProofKitOnboardingProfileName.normalized(displayName) else {
            UserDefaults.standard.removeObject(forKey: profileDisplayNameKey)
            UserDefaults.standard.synchronize()
            return
        }

        UserDefaults.standard.set(normalizedName, forKey: profileDisplayNameKey)
        UserDefaults.standard.synchronize()
    }

    static func pendingProfileDisplayName() -> String? {
        ProofKitOnboardingProfileName.normalized(
            UserDefaults.standard.string(forKey: profileDisplayNameKey)
        )
    }

    static func markAccountCreationAttempt(email: String?) {
        guard pendingSeed() != nil else { return }

        UserDefaults.standard.set(Date(), forKey: accountCreationAttemptedAtKey)

        if let normalizedEmail = normalizedEmail(email) {
            UserDefaults.standard.set(normalizedEmail, forKey: accountCreationEmailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: accountCreationEmailKey)
        }

        UserDefaults.standard.synchronize()
    }

    static func hasPendingAccountCreationAttempt(matching email: String?) -> Bool {
        guard hasAnyPendingAccountCreationAttempt() else {
            return false
        }

        guard let storedEmail = UserDefaults.standard.string(forKey: accountCreationEmailKey) else {
            return true
        }

        return normalizedEmail(email) == storedEmail
    }

    static func hasAnyPendingAccountCreationAttempt() -> Bool {
        guard pendingSeed() != nil,
              let attemptedAt = UserDefaults.standard.object(forKey: accountCreationAttemptedAtKey) as? Date else {
            return false
        }

        guard Date().timeIntervalSince(attemptedAt) <= accountCreationAttemptMaxAge else {
            clearAccountCreationAttempt()
            return false
        }

        return true
    }

    static func clearUnlessAccountCreationAttemptPending() {
        if hasAnyPendingAccountCreationAttempt() {
            return
        }

        clear()
    }

    static func clearAccountCreationAttempt() {
        UserDefaults.standard.removeObject(forKey: accountCreationAttemptedAtKey)
        UserDefaults.standard.removeObject(forKey: accountCreationEmailKey)
        UserDefaults.standard.synchronize()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: seedIDKey)
        UserDefaults.standard.removeObject(forKey: seedSavedAtKey)
        UserDefaults.standard.removeObject(forKey: profileDisplayNameKey)
        clearAccountCreationAttempt()
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        let normalized = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalized, !normalized.isEmpty else {
            return nil
        }

        return normalized
    }
}

struct ProofKitOnboardingPurposeView: View {
    let onSelect: (CaseCategory) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: topOffset(for: proxy))

                VStack(alignment: .leading, spacing: titleSpacing(for: proxy)) {
                    Text("What are you building proof for?")
                        .font(.system(size: titleSize(for: proxy), weight: .bold, design: .rounded))
                        .tracking(-0.75)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("ProofKit will create the right packet structure for your situation.")
                        .font(.system(size: subtitleSize(for: proxy), weight: .regular, design: .rounded))
                        .tracking(-0.18)
                        .foregroundStyle(ProofKitAuthPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .proofKitAppear(delay: reduceMotion ? 0 : 0.04)

                Spacer()
                    .frame(height: listTopSpacing(for: proxy))

                ScrollView {
                    VStack(spacing: cardSpacing(for: proxy)) {
                        ForEach(CaseCategory.sharedOptions) { category in
                            Button {
                                ProofKitAuthHaptics.tap()
                                onSelect(category)
                            } label: {
                                CaseCategoryPurposeCard(
                                    category: category,
                                    isSelected: false,
                                    height: cardHeight(for: proxy),
                                    imageSize: imageSize(for: proxy),
                                    imageColumnWidth: imageColumnWidth(for: proxy),
                                    accessory: .chevron
                                )
                            }
                            .buttonStyle(ProofKitAuthPressButtonStyle())
                            .accessibilityLabel("\(category.onboardingPurposeTitle). \(category.onboardingPurposeOutcome)")
                            .accessibilityHint("Double tap to choose this purpose and continue.")
                        }
                    }
                    .proofKitAppear(delay: reduceMotion ? 0 : 0.08)
                    .padding(.bottom, bottomPadding(for: proxy))
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, ProofKitAuthLayout.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func topOffset(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return max(proxy.safeAreaInsets.top + 78, 116)
        }

        return max(proxy.safeAreaInsets.top + 86, 132)
    }

    private func titleSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 8 : 10
    }

    private func listTopSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 14 : 18
    }

    private func cardSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 12 : 13
    }

    private func cardHeight(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 136 : 142
    }

    private func imageSize(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 126 : 134
    }

    private func imageColumnWidth(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.width < 370 ? 126 : 136
    }

    private func bottomPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.size.height < 740 ? 26 : 36, proxy.safeAreaInsets.bottom + 22)
    }

    private func titleSize(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return proxy.size.width < 370 ? 26 : 27
        }

        return proxy.size.width < 370 ? 28 : 30
    }

    private func subtitleSize(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return proxy.size.width < 370 ? 14.5 : 15.5
        }

        return proxy.size.width < 370 ? 15.5 : 16.5
    }
}

#Preview("Purpose onboarding") {
    ZStack {
        ProofKitAuthPalette.background
            .ignoresSafeArea()

        ProofKitOnboardingPurposeView { _ in
            // Preview-only no-op.
        }
    }
    .preferredColorScheme(.dark)
}
