import SwiftUI
import UIKit

struct ProofKitAuthView: View {
    private let services: ServiceContainer
    private let onAuthenticated: (ProofKitAccountSession, Bool) async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var authMode: ProofKitAuthMode = .welcome
    @State private var emailBackDestination: ProofKitAuthMode = .landing
    @State private var isSignUpMode = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationPassword = ""
    @State private var isWorking = false
    @State private var notice: ProofKitAuthNotice?
    @FocusState private var focusedField: ProofKitAuthField?

    init(
        services: ServiceContainer,
        initialErrorMessage: String? = nil,
        onAuthenticated: @escaping (ProofKitAccountSession, Bool) async -> Void
    ) {
        self.services = services
        self.onAuthenticated = onAuthenticated
        _notice = State(
            initialValue: initialErrorMessage.map {
                ProofKitAuthNotice(title: "Authentication Unavailable", message: $0)
            }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ProofKitAuthPalette.background
                    .ignoresSafeArea()

                Group {
                    switch authMode {
                    case .welcome:
                        welcomeContent(in: proxy)
                    case .landing:
                        landingContent(in: proxy)
                    case .email:
                        emailContent(in: proxy)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .animation(ProofKitMotion.softSpring, value: authMode)
                .animation(ProofKitMotion.quick, value: isSignUpMode)

                if authMode != .welcome {
                    backButton(topInset: proxy.safeAreaInsets.top)
                }

                if isWorking {
                    workingOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func welcomeContent(in proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: welcomeHeroTopOffset(for: proxy))

            Image("RookLogin")
                .resizable()
                .scaledToFit()
                .frame(
                    width: ProofKitAuthLayout.rookHeroSize(for: proxy),
                    height: ProofKitAuthLayout.rookHeroSize(for: proxy)
                )
                .accessibilityHidden(true)
                .proofKitAppear(delay: reduceMotion ? 0 : 0.04)

            Spacer()
                .frame(height: welcomeHeroTitleSpacing(for: proxy))

            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to ProofKit")
                    .font(.system(size: welcomeTitleSize(for: proxy), weight: .bold, design: .rounded))
                    .tracking(-0.9)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                VStack(alignment: .leading, spacing: 13) {
                    Text("Capture, organize, and export proof without friction.")

                    Text("Built so your evidence is ready when it matters.")
                }
                .font(.system(size: welcomeSubtitleSize(for: proxy), weight: .regular, design: .rounded))
                .tracking(-0.25)
                .foregroundStyle(ProofKitAuthPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .proofKitAppear(delay: reduceMotion ? 0 : 0.08)

            Spacer(minLength: welcomeButtonSpacerMinLength(for: proxy))

            VStack(spacing: welcomeFooterSpacing(for: proxy)) {
                Button {
                    ProofKitAuthHaptics.tap()
                    beginOnboarding()
                } label: {
                    Text("Get Started")
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
                .disabled(isWorking)

                Button {
                    ProofKitAuthHaptics.tap()
                    showSignInOptions()
                } label: {
                    HStack(spacing: 0) {
                        Text("Already have an account? ")
                            .foregroundStyle(ProofKitAuthPalette.secondaryText)

                        Text("Sign in")
                            .foregroundStyle(.white)
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .tracking(-0.15)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProofKitAuthPressButtonStyle())
                .accessibilityLabel("Already have an account? Sign in")
            }
            .proofKitAppear(delay: reduceMotion ? 0 : 0.12)
            .padding(.bottom, welcomeBottomPadding(for: proxy))
        }
        .padding(.horizontal, ProofKitAuthLayout.horizontalPadding)
    }

    private func landingContent(in proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: landingHeroTopOffset(for: proxy))

            Image("RookLogin")
                .resizable()
                .scaledToFit()
                .frame(
                    width: ProofKitAuthLayout.rookHeroSize(for: proxy),
                    height: ProofKitAuthLayout.rookHeroSize(for: proxy)
                )
                .accessibilityHidden(true)
                .proofKitAppear(delay: reduceMotion ? 0 : 0.04)

            Spacer()
                .frame(height: landingHeroTitleSpacing(for: proxy))

            authHeadline(
                title: "Welcome back",
                subtitle: "Sign in to your account"
            )
            .proofKitAppear(delay: reduceMotion ? 0 : 0.08)

            Spacer(minLength: landingButtonSpacerMinLength(for: proxy))

            authButtonStack(
                bottomInset: proxy.safeAreaInsets.bottom,
                isCompactHeight: proxy.size.height < 740
            )
                .proofKitAppear(delay: reduceMotion ? 0 : 0.12)
        }
        .padding(.horizontal, ProofKitAuthLayout.horizontalPadding)
    }

    private func emailContent(in proxy: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: max(proxy.safeAreaInsets.top + 94, 132))

                Image("RookLogin")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: ProofKitAuthLayout.rookHeroSize(for: proxy),
                        height: ProofKitAuthLayout.rookHeroSize(for: proxy)
                    )
                    .accessibilityHidden(true)

                Spacer()
                    .frame(height: 34)

                authHeadline(
                    title: isSignUpMode ? "Create account" : "Welcome back",
                    subtitle: isSignUpMode ? "Sign up with your email" : "Sign in with your email"
                )

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .proofKitAuthFieldStyle()

                    SecureField("Password", text: $password)
                        .textContentType(isSignUpMode ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(isSignUpMode ? .next : .go)
                        .onSubmit {
                            if isSignUpMode {
                                focusedField = .confirmationPassword
                            } else {
                                submitEmailPasswordAuth()
                            }
                        }
                        .proofKitAuthFieldStyle()

                    if isSignUpMode {
                        SecureField("Confirm password", text: $confirmationPassword)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirmationPassword)
                            .submitLabel(.go)
                            .onSubmit { submitEmailPasswordAuth() }
                            .proofKitAuthFieldStyle()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 34)

                Button {
                    ProofKitAuthHaptics.tap()
                    submitEmailPasswordAuth()
                } label: {
                    Text(isSignUpMode ? "Create account" : "Sign in")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: ProofKitAuthLayout.buttonHeight)
                        .background {
                            Capsule(style: .continuous)
                                .fill(ProofKitAuthPalette.emailButton)
                        }
                }
                .buttonStyle(ProofKitAuthPressButtonStyle())
                .disabled(isWorking)
                .padding(.top, 18)

                Button {
                    ProofKitAuthHaptics.tap()
                    sendMagicLink()
                } label: {
                    Text("Email me a magic link")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProofKitAuthPressButtonStyle())
                .disabled(isWorking)
                .padding(.top, 2)

                Spacer()
                    .frame(height: 12)

                authToggle
                    .padding(.bottom, max(34, proxy.safeAreaInsets.bottom + 24))
            }
            .padding(.horizontal, ProofKitAuthLayout.horizontalPadding)
            .frame(minHeight: proxy.size.height)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func authHeadline(title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 21, weight: .regular, design: .rounded))
                .tracking(-0.2)
                .foregroundStyle(ProofKitAuthPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func authButtonStack(bottomInset: CGFloat, isCompactHeight: Bool) -> some View {
        VStack(spacing: 14) {
            ProofKitAuthButton(
                title: "Continue with Apple",
                foreground: .white,
                background: .black,
                fontSize: 24,
                icon: {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 25, weight: .semibold))
                        .offset(y: -1)
                },
                action: { authenticateWithOAuth(.apple) }
            )

            ProofKitAuthButton(
                title: "Continue with Google",
                foreground: ProofKitAuthPalette.googleText,
                background: ProofKitAuthPalette.googleButton,
                fontSize: 23,
                icon: {
                    ProofKitGoogleMark()
                        .frame(width: 31, height: 31)
                },
                action: { authenticateWithOAuth(.google) }
            )

            ProofKitAuthButton(
                title: "Continue with Email",
                foreground: .white,
                background: ProofKitAuthPalette.emailButton,
                fontSize: 22,
                icon: { EmptyView() },
                action: {
                    showEmailAuth(signUp: false, backDestination: .landing)
                }
            )

            authToggle
                .padding(.top, 11)
        }
        .padding(.bottom, max(isCompactHeight ? 20 : 44, bottomInset + (isCompactHeight ? 8 : 14)))
    }

    private var authToggle: some View {
        Button {
            ProofKitAuthHaptics.tap()
            showEmailAuth(
                signUp: !isSignUpMode,
                backDestination: authMode == .email ? emailBackDestination : .landing,
                focusDelay: 0
            )
        } label: {
            HStack(spacing: 0) {
                Text(isSignUpMode ? "Already have an account? " : "Don't have an account? ")
                    .foregroundStyle(ProofKitAuthPalette.secondaryText)

                Text(isSignUpMode ? "Sign in" : "Sign up")
                    .foregroundStyle(.white)
                    .fontWeight(.bold)
            }
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .tracking(-0.15)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ProofKitAuthPressButtonStyle())
        .accessibilityLabel(isSignUpMode ? "Already have an account? Sign in" : "Don't have an account? Sign up")
    }

    private func backButton(topInset: CGFloat) -> some View {
        Button {
            ProofKitAuthHaptics.tap()
            if authMode == .email {
                focusedField = nil
                authMode = emailBackDestination

                if emailBackDestination == .landing {
                    isSignUpMode = false
                    confirmationPassword = ""
                }
            } else {
                showWelcome()
            }
        } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(ProofKitAuthPalette.backArrow)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(ProofKitAuthPalette.backCircle)
                }
                .contentShape(Circle())
        }
        .buttonStyle(ProofKitAuthPressButtonStyle())
        .padding(.leading, 20)
        .padding(.top, max(70, topInset + 23))
        .accessibilityLabel(backButtonAccessibilityLabel)
    }

    private var workingOverlay: some View {
        ZStack {
            ProofKitAuthPalette.background.opacity(0.56)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.08)

                Text("One moment…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.58))
            }
        }
        .transition(.opacity)
    }

    private func landingHeroTopOffset(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return max(proxy.safeAreaInsets.top + 24, proxy.size.height * 0.052)
        }

        let referenceOffset = proxy.size.height * 0.108
        return max(proxy.safeAreaInsets.top + 48, min(referenceOffset, proxy.safeAreaInsets.top + 72))
    }

    private func landingHeroTitleSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 12 : 24
    }

    private func landingButtonSpacerMinLength(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 6 : 18
    }

    private func welcomeHeroTopOffset(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return max(proxy.safeAreaInsets.top + 30, proxy.size.height * 0.07)
        }

        return max(proxy.safeAreaInsets.top + 54, proxy.size.height * 0.095)
    }

    private func welcomeHeroTitleSpacing(for proxy: GeometryProxy) -> CGFloat {
        if proxy.size.height < 740 {
            return 22
        }

        return 36
    }

    private func welcomeTitleSize(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.width < 370 ? 31 : 34
    }

    private func welcomeSubtitleSize(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.width < 370 ? 18 : 20
    }

    private func welcomeButtonSpacerMinLength(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 22 : 28
    }

    private func welcomeFooterSpacing(for proxy: GeometryProxy) -> CGFloat {
        proxy.size.height < 740 ? 18 : 24
    }

    private func welcomeBottomPadding(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.size.height < 740 ? 28 : 42, proxy.safeAreaInsets.bottom + 24)
    }

    private var backButtonAccessibilityLabel: String {
        if authMode == .email {
            return emailBackDestination == .welcome ? "Back to welcome" : "Back to sign in options"
        }

        return "Back to welcome"
    }

    private func beginOnboarding() {
        showEmailAuth(signUp: true, backDestination: .welcome)
    }

    private func showSignInOptions() {
        focusedField = nil
        isSignUpMode = false
        confirmationPassword = ""
        emailBackDestination = .landing
        authMode = .landing
    }

    private func showWelcome() {
        focusedField = nil
        isSignUpMode = false
        confirmationPassword = ""
        authMode = .welcome
    }

    private func showEmailAuth(
        signUp: Bool,
        backDestination: ProofKitAuthMode,
        focusDelay: TimeInterval = 0.28
    ) {
        isSignUpMode = signUp

        if !signUp {
            confirmationPassword = ""
        }

        emailBackDestination = backDestination
        authMode = .email

        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay) {
            focusedField = .email
        }
    }

    private func authenticateWithOAuth(_ provider: ProofKitOAuthProvider) {
        guard ensureConfigured() else { return }
        guard !isWorking else { return }
        isWorking = true

        Task { @MainActor in
            do {
                let session = try await services.account.signInWithOAuth(provider)
                await onAuthenticated(session, false)
            } catch {
                notice = ProofKitAuthNotice(title: "Couldn’t Sign In", message: Self.message(for: error))
            }
            isWorking = false
        }
    }

    private func submitEmailPasswordAuth() {
        guard ensureConfigured() else { return }
        guard !isWorking else { return }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@") else {
            notice = ProofKitAuthNotice(title: "Email Required", message: "Enter the email address for your ProofKit account.")
            focusedField = .email
            return
        }

        guard password.count >= 8 else {
            notice = ProofKitAuthNotice(title: "Password Required", message: "Enter a password with at least 8 characters.")
            focusedField = .password
            return
        }

        if isSignUpMode, password != confirmationPassword {
            notice = ProofKitAuthNotice(title: "Passwords Don’t Match", message: "Confirm your password before creating your account.")
            focusedField = .confirmationPassword
            return
        }

        isWorking = true
        Task { @MainActor in
            do {
                let session: ProofKitAccountSession
                if isSignUpMode {
                    session = try await services.account.signUpWithPassword(email: cleanEmail, password: password)
                } else {
                    session = try await services.account.signInWithPassword(email: cleanEmail, password: password)
                }
                await onAuthenticated(session, isSignUpMode)
            } catch {
                notice = ProofKitAuthNotice(title: isSignUpMode ? "Couldn’t Create Account" : "Couldn’t Sign In", message: Self.message(for: error))
            }
            isWorking = false
        }
    }

    private func sendMagicLink() {
        guard ensureConfigured() else { return }
        guard !isWorking else { return }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanEmail.contains("@") else {
            notice = ProofKitAuthNotice(title: "Email Required", message: "Enter your email address and we’ll send a sign-in link.")
            focusedField = .email
            return
        }

        isWorking = true
        Task { @MainActor in
            do {
                try await services.account.sendMagicLink(email: cleanEmail)
                notice = ProofKitAuthNotice(
                    title: "Check Your Email",
                    message: "We sent a secure ProofKit sign-in link to \(cleanEmail)."
                )
            } catch {
                notice = ProofKitAuthNotice(title: "Couldn’t Send Link", message: Self.message(for: error))
            }
            isWorking = false
        }
    }

    private func ensureConfigured() -> Bool {
        guard services.account.isConfigured else {
            notice = ProofKitAuthNotice(
                title: "Authentication Not Configured",
                message: "Add Supabase URL and publishable-key configuration to this build before signing in."
            )
            return false
        }

        return true
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

struct ProofKitAuthLaunchView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ProofKitAuthPalette.background
                    .ignoresSafeArea()

                VStack(spacing: 26) {
                    Image("RookLogin")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: ProofKitAuthLayout.rookHeroSize(for: proxy),
                            height: ProofKitAuthLayout.rookHeroSize(for: proxy)
                        )
                        .accessibilityHidden(true)

                    ProgressView()
                        .tint(.white)
                }
                .proofKitAppear()
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct ProofKitSignupSuccessView: View {
    let email: String?

    var body: some View {
        ZStack {
            ProofKitAuthPalette.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background {
                        Circle()
                            .fill(ProofKitAuthPalette.emailButton)
                    }

                Text("Account created")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(email.map { "Opening your private ProofKit workspace for \($0)." } ?? "Opening your private ProofKit workspace.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(ProofKitAuthPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }
            .proofKitAppear()
        }
        .preferredColorScheme(.dark)
    }
}

private struct ProofKitAuthButton<Icon: View>: View {
    let title: String
    let foreground: Color
    let background: Color
    let fontSize: CGFloat
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button {
            ProofKitAuthHaptics.tap()
            action()
        } label: {
            HStack(spacing: 13) {
                icon()

                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .tracking(-0.25)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: ProofKitAuthLayout.buttonHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(background)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(ProofKitAuthPressButtonStyle())
    }
}

private enum ProofKitAuthHaptics {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.72)
    }
}

private struct ProofKitGoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 29, weight: .bold, design: .default))
            .foregroundStyle(
                AngularGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.96),
                        Color(red: 0.20, green: 0.66, blue: 0.33),
                        Color(red: 0.98, green: 0.74, blue: 0.18),
                        Color(red: 0.92, green: 0.26, blue: 0.21),
                        Color(red: 0.26, green: 0.52, blue: 0.96)
                    ],
                    center: .center
                )
            )
            .accessibilityHidden(true)
    }
}

private struct ProofKitAuthPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct ProofKitAuthNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum ProofKitAuthMode: Hashable {
    case welcome
    case landing
    case email
}

private enum ProofKitAuthField: Hashable {
    case email
    case password
    case confirmationPassword
}

private enum ProofKitAuthLayout {
    static let horizontalPadding: CGFloat = 20
    static let buttonHeight: CGFloat = 55
    static let welcomeButtonHeight: CGFloat = 62

    static func rookHeroSize(for proxy: GeometryProxy) -> CGFloat {
        min(334, max(252, proxy.size.height * 0.38))
    }
}

private enum ProofKitAuthPalette {
    static let background = dynamicColor(
        light: UIColor(red: 0.972, green: 0.968, blue: 0.958, alpha: 1),
        dark: UIColor(red: 0.047, green: 0.059, blue: 0.078, alpha: 1)
    )
    static let secondaryText = Color(red: 178 / 255, green: 176 / 255, blue: 181 / 255)
    static let backCircle = Color.white.opacity(0.055)
    static let backArrow = Color.white.opacity(0.44)
    static let googleButton = Color(red: 246 / 255, green: 246 / 255, blue: 246 / 255)
    static let googleText = Color(red: 34 / 255, green: 34 / 255, blue: 36 / 255)
    static let emailButton = dynamicColor(
        light: .black,
        dark: UIColor(red: 0.16, green: 0.56, blue: 1.00, alpha: 1)
    )
    static let fieldBackground = Color.white.opacity(0.085)
    static let fieldStroke = Color.white.opacity(0.11)

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

private extension View {
    func proofKitAuthFieldStyle() -> some View {
        self
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .tint(ProofKitAuthPalette.emailButton)
            .padding(.horizontal, 18)
            .frame(height: 56)
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

#Preview("Auth") {
    ProofKitAuthView(services: .live) { _, _ in
        // Preview-only no-op.
    }
}
