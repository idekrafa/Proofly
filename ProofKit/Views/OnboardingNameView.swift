import Combine
import SwiftUI
import UIKit

final class ProofKitKeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0

    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter

        observers.append(
            notificationCenter.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }

                self?.height = max(0, frame.height)
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.height = 0
            }
        )
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }
}

enum ProofKitOnboardingProfileName {
    static let maximumLength = 80

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }

        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }

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
    @StateObject private var keyboard = ProofKitKeyboardObserver()
    @State private var didAttemptInvalidSubmit = false
    @State private var didAutoFocusNameField = false
    @State private var userDismissedNameKeyboard = false

    private var normalizedDisplayName: String? {
        ProofKitOnboardingProfileName.normalized(displayName)
    }

    private var hasValidDisplayName: Bool {
        normalizedDisplayName != nil
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
                            .tracking(-0.9)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("What should we call you?")

                        Text("Rook will use your name to personalize Proofly. You can change it at any time.")
                            .font(.system(size: subtitleSize(for: proxy), weight: .regular, design: .rounded))
                            .tracking(-0.22)
                            .lineSpacing(2)
                            .foregroundStyle(ProofKitAuthPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    nameField

                    if didAttemptInvalidSubmit && !hasValidDisplayName {
                        invalidHelper
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ProofKitNameSupabaseNote()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .proofKitAppear(delay: reduceMotion ? 0 : 0.08)

                Spacer(minLength: buttonSpacerMinLength(for: proxy))

                continueButton
                    .proofKitAppear(delay: reduceMotion ? 0 : 0.12)
                    .padding(.bottom, bottomPadding(for: proxy))
            }
            .padding(.horizontal, ProofKitAuthLayout.horizontalPadding)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .offset(y: keyboard.height > 0 ? -130 : 0)
            .animation(.easeOut(duration: 0.25), value: keyboard.height)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            guard !reduceMotion else { return }
            guard !didAutoFocusNameField else { return }

            didAutoFocusNameField = true

            try? await Task.sleep(nanoseconds: 350_000_000)

            guard !Task.isCancelled else { return }
            guard !userDismissedNameKeyboard else { return }
            guard !isNameFocused else { return }

            isNameFocused = true
        }
        .onChange(of: isNameFocused) { _, focused in
            if !focused && didAutoFocusNameField {
                userDismissedNameKeyboard = true
            }
        }
    }

    private var nameField: some View {
        TextField("Your name", text: $displayName)
            .textContentType(.name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled(false)
            .focused($isNameFocused)
            .submitLabel(.done)
            .onSubmit {
                userDismissedNameKeyboard = true
                isNameFocused = false

                if !hasValidDisplayName {
                    showInvalidHelper(shouldFocusField: false)
                }
            }
            .proofKitAuthFieldStyle()
            .onChange(of: displayName) { _, newValue in
                if newValue.count > ProofKitOnboardingProfileName.maximumLength {
                    displayName = String(newValue.prefix(ProofKitOnboardingProfileName.maximumLength))
                    return
                }

                if ProofKitOnboardingProfileName.normalized(newValue) != nil {
                    withAnimation(ProofKitMotion.quick) {
                        didAttemptInvalidSubmit = false
                    }
                }
            }
            .accessibilityLabel("Your name")
            .accessibilityHint("First name or nickname is okay.")
    }

    private var invalidHelper: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .accessibilityHidden(true)

            Text("Add a name or nickname to continue.")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .tracking(-0.05)
        }
        .foregroundStyle(ProofKitAuthPalette.secondaryText)
        .padding(.top, -2)
        .accessibilityElement(children: .combine)
    }

    private var continueButton: some View {
        ZStack {
            Button {
                ProofKitAuthHaptics.tap()
                continueIfPossible()
            } label: {
                Text("Continue")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .tracking(-0.25)
                    .foregroundStyle(hasValidDisplayName ? .white : ProofKitAuthPalette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: ProofKitAuthLayout.welcomeButtonHeight)
                    .background {
                        Capsule(style: .continuous)
                            .fill(ProofKitAuthPalette.emailButton)
                    }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(ProofKitAuthPressButtonStyle())
            .disabled(!hasValidDisplayName)
            .accessibilityHint(hasValidDisplayName ? "Saves your name and continues onboarding." : "Enter a name or nickname to continue.")

            if !hasValidDisplayName {
                Capsule(style: .continuous)
                    .fill(Color.clear)
                    .contentShape(Capsule(style: .continuous))
                    .onTapGesture { showInvalidHelper() }
                    .accessibilityHidden(true)
            }
        }
    }

    private func continueIfPossible() {
        guard let normalizedDisplayName else {
            showInvalidHelper()
            return
        }

        displayName = normalizedDisplayName
        didAttemptInvalidSubmit = false
        isNameFocused = false
        onContinue(normalizedDisplayName)
    }

    private func showInvalidHelper(shouldFocusField: Bool = true) {
        ProofKitAuthHaptics.tap()
        withAnimation(ProofKitMotion.quick) {
            didAttemptInvalidSubmit = true
        }

        if shouldFocusField {
            userDismissedNameKeyboard = false
            isNameFocused = true
        }
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
            return proxy.size.width < 370 ? 32 : 34
        }

        return proxy.size.width < 370 ? 35 : 38
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


private struct ProofKitNameSupabaseNote: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(ProofKitAuthPalette.fieldBackground)
                }
                .accessibilityHidden(true)

            Text("Your name is used only to personalize your profile.")
                .font(.system(size: 14.5, weight: .regular, design: .rounded))
                .tracking(-0.08)
                .lineSpacing(1.5)
                .foregroundStyle(ProofKitAuthPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(ProofKitAuthPalette.fieldBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(ProofKitAuthPalette.fieldStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Name onboarding") {
    ZStack {
        ProofKitAuthPalette.background
            .ignoresSafeArea()

        ProofKitOnboardingNameView(displayName: .constant("")) { _ in
            // Preview-only no-op.
        }
    }
    .preferredColorScheme(.dark)
}
