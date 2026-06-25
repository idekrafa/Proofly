import SwiftUI

struct ProofKitOnboardingPrivacyView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: heroTopOffset(for: proxy))

                ProofKitAuthRookImage(
                    imageName: "RookPrivacy",
                    size: ProofKitAuthLayout.rookHeroSize(for: proxy)
                )
                    .proofKitAppear(delay: reduceMotion ? 0 : 0.04)

                Spacer()
                    .frame(height: heroTitleSpacing(for: proxy))

                VStack(alignment: .leading, spacing: contentSpacing(for: proxy)) {
                    VStack(alignment: .leading, spacing: titleSpacing(for: proxy)) {
                        Text("Privacy promise")
                            .font(.system(size: titleSize(for: proxy), weight: .bold, design: .rounded))
                            .tracking(-0.85)
                            .foregroundStyle(.white)

                        Text("Your evidence stays on your device unless you choose otherwise.")
                            .font(.system(size: subtitleSize(for: proxy), weight: .regular, design: .rounded))
                            .tracking(-0.25)
                            .foregroundStyle(ProofKitAuthPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: rowSpacing(for: proxy)) {
                        ProofKitPrivacyPromiseRow(
                            symbolName: "lock.shield.fill",
                            title: String(localized: "Local by default"),
                            message: String(localized: "Evidence stays local by default.")
                        )

                        ProofKitPrivacyPromiseRow(
                            symbolName: "person.crop.circle.fill",
                            title: String(localized: "Scoped to your account"),
                            message: String(localized: "Separate local workspace per account.")
                        )

                        ProofKitPrivacyPromiseRow(
                            symbolName: "square.and.arrow.up.fill",
                            title: String(localized: "You decide what leaves"),
                            message: String(localized: "Exports only when you choose.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .proofKitAppear(delay: reduceMotion ? 0 : 0.08)

                Spacer(minLength: buttonSpacerMinLength(for: proxy))

                Button {
                    ProofKitAuthHaptics.tap()
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .tracking(-0.25)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: ProofKitAuthLayout.welcomeButtonHeight)
                        .background {
                            Capsule(style: .continuous)
                                .fill(ProofKitAuthPalette.emailButton)
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(ProofKitAuthPressButtonStyle())
                .proofKitAppear(delay: reduceMotion ? 0 : 0.12)
                .padding(.bottom, bottomPadding(for: proxy))
            }
            .padding(.horizontal, ProofKitAuthLayout.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func heroTopOffset(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return max(proxy.safeAreaInsets.top + 38, proxy.size.height * 0.075)
        }

        return max(proxy.safeAreaInsets.top + 38, proxy.size.height * 0.095)
    }

    private func heroTitleSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 8 : 16
    }

    private func contentSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 10 : 15
    }

    private func titleSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 7 : 10
    }

    private func rowSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 7 : 10
    }

    private func titleSize(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return proxy.size.width < 370 ? 28 : 29
        }

        return proxy.size.width < 370 ? 31 : 34
    }

    private func subtitleSize(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return proxy.size.width < 370 ? 15.5 : 16
        }

        return proxy.size.width < 370 ? 18 : 20
    }

    private func buttonSpacerMinLength(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 8 : 16
    }

    private func bottomPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.size.height < 740 ? 20 : 34, proxy.safeAreaInsets.bottom + (proxy.size.height < 740 ? 12 : 18))
    }
}

private struct ProofKitPrivacyPromiseRow: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(ProofKitAuthPalette.fieldBackground)
                }
                .overlay {
                    Circle()
                        .stroke(ProofKitAuthPalette.fieldStroke, lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(-0.12)
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .tracking(-0.08)
                    .foregroundStyle(ProofKitAuthPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ProofKitAuthPalette.fieldBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ProofKitAuthPalette.fieldStroke, lineWidth: 1)
        }
    }
}

#Preview("Privacy onboarding") {
    ZStack {
        ProofKitAuthPalette.background
            .ignoresSafeArea()

        ProofKitOnboardingPrivacyView {
            // Preview-only no-op.
        }
    }
    .preferredColorScheme(.dark)
}
