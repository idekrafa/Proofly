import SwiftUI

struct ProofKitOnboardingPurpose: Hashable, Identifiable {
    let id: String
    let imageName: String
    let title: String
    let outcome: String

    static let rental = ProofKitOnboardingPurpose(
        id: "rental",
        imageName: "RookPurposeRental",
        title: "Rent or lease issue",
        outcome: "Build a clean repair, deposit, or landlord timeline."
    )

    static let refund = ProofKitOnboardingPurpose(
        id: "refund",
        imageName: "RookPurposeRefund",
        title: "Get a refund",
        outcome: "Organize receipts, screenshots, and messages."
    )

    static let college = ProofKitOnboardingPurpose(
        id: "college",
        imageName: "RookPurposeCollege",
        title: "School or college issue",
        outcome: "Keep deadlines, emails, essays, and records together."
    )

    static let other = ProofKitOnboardingPurpose(
        id: "other",
        imageName: "RookPurposeOther",
        title: "Not sure yet?",
        outcome: "ProofKit has your back —\norganize proof for whatever\nlife throws at you."
    )

    static let all: [ProofKitOnboardingPurpose] = [
        .rental,
        .refund,
        .college,
        .other
    ]
}

struct ProofKitOnboardingFirstCaseSeed: Hashable, Identifiable {
    let id: String
    let title: String
    let caseType: CaseType
    let caseTypeLabel: String
    let summary: String
    let suggestedEvidence: [String]
    let prompt: String?

    var notesText: String {
        notesText(details: "")
    }

    func notesText(details: String) -> String {
        var sections: [String] = []
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        sections.append("Selected onboarding category: \(caseTypeLabel)")

        if !trimmedDetails.isEmpty {
            sections.append("What happened:\n\(trimmedDetails)")
        }

        if let prompt {
            sections.append(prompt)
        }

        if !suggestedEvidence.isEmpty {
            let bullets = suggestedEvidence
                .map { "• \($0)" }
                .joined(separator: "\n")
            sections.append("Suggested evidence:\n\(bullets)")
        }

        return sections.joined(separator: "\n\n")
    }
}

extension ProofKitOnboardingPurpose {
    var firstCaseSeed: ProofKitOnboardingFirstCaseSeed {
        switch id {
        case Self.rental.id:
            ProofKitOnboardingFirstCaseSeed(
                id: id,
                title: "Apartment issue timeline",
                caseType: .tenantLandlord,
                caseTypeLabel: "Rent / lease",
                summary: "A draft timeline for rent, lease, repair, deposit, or landlord records.",
                suggestedEvidence: [
                    "Repair requests",
                    "Landlord messages",
                    "Move-in photos",
                    "Deposit/payment screenshots",
                    "Lease documents"
                ],
                prompt: nil
            )
        case Self.refund.id:
            ProofKitOnboardingFirstCaseSeed(
                id: id,
                title: "Refund request timeline",
                caseType: .refundWarrantyIssue,
                caseTypeLabel: "Refund / warranty",
                summary: "A draft timeline for receipts, support conversations, delivery records, and refund decisions.",
                suggestedEvidence: [
                    "Order screenshots",
                    "Support chats",
                    "Receipts",
                    "Delivery photos"
                ],
                prompt: nil
            )
        case Self.college.id:
            ProofKitOnboardingFirstCaseSeed(
                id: id,
                title: "School / college timeline",
                caseType: .other,
                caseTypeLabel: "School / college",
                summary: "A draft packet for school or college deadlines, emails, essays, documents, and confirmations.",
                suggestedEvidence: [
                    "Deadlines",
                    "Emails",
                    "Essays",
                    "Documents",
                    "Confirmations"
                ],
                prompt: nil
            )
        default:
            ProofKitOnboardingFirstCaseSeed(
                id: Self.other.id,
                title: "My proof timeline",
                caseType: .general,
                caseTypeLabel: "Something else",
                summary: "A flexible draft packet for organizing what happened and the records that prove it.",
                suggestedEvidence: [
                    "What happened?",
                    "Photos or screenshots",
                    "Messages or emails",
                    "Receipts or documents",
                    "Important dates"
                ],
                prompt: "Start by answering: What happened?"
            )
        }
    }

    static func firstCaseSeed(for id: String) -> ProofKitOnboardingFirstCaseSeed? {
        all.first { $0.id == id }?.firstCaseSeed
    }
}

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

        return ProofKitOnboardingPurpose.firstCaseSeed(for: seedID)
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
    let onSelect: (ProofKitOnboardingPurpose) -> Void

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
                        ForEach(ProofKitOnboardingPurpose.all) { purpose in
                            ProofKitPurposeCard(
                                purpose: purpose,
                                height: cardHeight(for: proxy),
                                imageSize: imageSize(for: proxy),
                                imageColumnWidth: imageColumnWidth(for: proxy)
                            ) {
                                onSelect(purpose)
                            }
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

private struct ProofKitPurposeCard: View {
    let purpose: ProofKitOnboardingPurpose
    let height: CGFloat
    let imageSize: CGFloat
    let imageColumnWidth: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            ProofKitAuthHaptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Image(purpose.imageName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: imageSize, height: imageSize)
                        .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 9)
                }
                .frame(width: imageColumnWidth, height: height, alignment: .center)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(purpose.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .tracking(-0.18)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)
                    }

                    Text(purpose.outcome)
                        .font(.system(size: 14.5, weight: .regular, design: .rounded))
                        .tracking(-0.08)
                        .foregroundStyle(ProofKitAuthPalette.secondaryText)
                        .lineLimit(3)
                        .minimumScaleFactor(0.86)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.36))
            }
            .padding(.leading, 2)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ProofKitAuthPalette.fieldBackground.opacity(0.96),
                                ProofKitAuthPalette.fieldBackground.opacity(0.70)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(ProofKitAuthPalette.fieldStroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(ProofKitAuthPressButtonStyle())
        .accessibilityLabel("\(purpose.title). \(purpose.outcome)")
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
