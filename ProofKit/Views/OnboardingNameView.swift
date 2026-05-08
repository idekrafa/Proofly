import SwiftUI

enum ProofKitOnboardingProfileName {
    static let maximumLength = 80

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }

        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }
        guard !collapsed.contains("@") else { return nil }
        guard collapsed.rangeOfCharacter(from: .letters) != nil else { return nil }

        let limited = String(collapsed.prefix(maximumLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return limited.isEmpty ? nil : limited
    }
}

struct ProofKitOnboardingNameView: View {
    @Binding var displayName: String
    let onContinue: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isNameFocused: Bool

    private var normalizedDisplayName: String? {
        ProofKitOnboardingProfileName.normalized(displayName)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: heroTopOffset(for: proxy))

                ProofKitAuthRookImage(
                    imageName: "RookLogin",
                    size: ProofKitAuthLayout.rookHeroSize(for: proxy)
                )
                    .proofKitAppear(delay: reduceMotion ? 0 : 0.04)

                Spacer()
                    .frame(height: heroTitleSpacing(for: proxy))

                VStack(alignment: .leading, spacing: contentSpacing(for: proxy)) {
                    VStack(alignment: .leading, spacing: titleSpacing(for: proxy)) {
                        Text("What should we call you?")
                            .font(.system(size: titleSize(for: proxy), weight: .bold, design: .rounded))
                            .tracking(-0.8)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Rook will use your name to personalize ProofKit. You can change it anytime.")
                            .font(.system(size: subtitleSize(for: proxy), weight: .regular, design: .rounded))
                            .tracking(-0.22)
                            .foregroundStyle(ProofKitAuthPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .focused($isNameFocused)
                        .submitLabel(.continue)
                        .onSubmit { continueIfPossible() }
                        .proofKitAuthFieldStyle()
                        .onChange(of: displayName) { _, newValue in
                            guard newValue.count > ProofKitOnboardingProfileName.maximumLength else { return }
                            displayName = String(newValue.prefix(ProofKitOnboardingProfileName.maximumLength))
                        }
                        .accessibilityLabel("Your name")

                    ProofKitNamePrivacyNote()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .proofKitAppear(delay: reduceMotion ? 0 : 0.08)

                Spacer(minLength: buttonSpacerMinLength(for: proxy))

                Button {
                    ProofKitAuthHaptics.tap()
                    continueIfPossible()
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
                .disabled(normalizedDisplayName == nil)
                .opacity(normalizedDisplayName == nil ? 0.52 : 1)
                .proofKitAppear(delay: reduceMotion ? 0 : 0.12)
                .padding(.bottom, bottomPadding(for: proxy))
            }
            .padding(.horizontal, ProofKitAuthLayout.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                isNameFocused = true
            }
        }
    }

    private func continueIfPossible() {
        guard let normalizedDisplayName else {
            isNameFocused = true
            return
        }

        displayName = normalizedDisplayName
        isNameFocused = false
        onContinue(normalizedDisplayName)
    }

    private func heroTopOffset(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return max(proxy.safeAreaInsets.top + 32, proxy.size.height * 0.07)
        }

        return max(proxy.safeAreaInsets.top + 50, proxy.size.height * 0.092)
    }

    private func heroTitleSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 14 : 24
    }

    private func contentSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 14 : 18
    }

    private func titleSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 8 : 10
    }

    private func titleSize(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return proxy.size.width < 370 ? 28 : 30
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
        proxy.size.height < 740 ? 8 : 18
    }

    private func bottomPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.size.height < 740 ? 20 : 34, proxy.safeAreaInsets.bottom + (proxy.size.height < 740 ? 12 : 18))
    }
}

private struct ProofKitNamePrivacyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(ProofKitAuthPalette.fieldBackground)
                }
                .accessibilityHidden(true)

            Text("Your name is used only to personalize your profile.")
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .tracking(-0.08)
                .foregroundStyle(ProofKitAuthPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
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

#Preview("Name onboarding") {
    ZStack {
        ProofKitAuthPalette.background
            .ignoresSafeArea()

        ProofKitOnboardingNameView(displayName: .constant("Sample User")) { _ in
            // Preview-only no-op.
        }
    }
    .preferredColorScheme(.dark)
}
