import Combine
import SwiftData
import SwiftUI

struct ProofKitRootView: View {
    private let services: ServiceContainer
    @StateObject private var authCoordinator: ProofKitAuthCoordinator

    init(services: ServiceContainer) {
        self.services = services
        _authCoordinator = StateObject(wrappedValue: ProofKitAuthCoordinator(services: services))
    }

    var body: some View {
        Group {
            switch authCoordinator.state {
            case .checking:
                ProofKitAuthLaunchView()

            case .signedOut:
                ProofKitAuthView(services: services) { session, isFirstTimeSignup, firstCaseSeed in
                    scheduleActivation(
                        session: session,
                        isFirstTimeSignup: isFirstTimeSignup,
                        firstCaseSeed: firstCaseSeed
                    )
                }

            case .authenticated(let scope, let firstCaseSeed):
                ContentView(accountSession: scope.session, firstCaseSeed: firstCaseSeed) {
                    authCoordinator.accountDidSignOut()
                }
                .id(scope.session.id)
                .environment(\.proofKitServices, scope.services)
                .modelContainer(scope.modelContainer)

            case .configurationError(let message):
                ProofKitAuthView(services: services, initialErrorMessage: message) { session, isFirstTimeSignup, firstCaseSeed in
                    scheduleActivation(
                        session: session,
                        isFirstTimeSignup: isFirstTimeSignup,
                        firstCaseSeed: firstCaseSeed
                    )
                }
            }
        }
        .task {
            await authCoordinator.bootstrapIfNeeded()
        }
        .onOpenURL { url in
            authCoordinator.handleAuthCallback(url)
        }
    }

    @MainActor
    private func scheduleActivation(
        session: ProofKitAccountSession,
        isFirstTimeSignup: Bool,
        firstCaseSeed: ProofKitOnboardingFirstCaseSeed?
    ) {
        Task { @MainActor in
            await Task.yield()
            await authCoordinator.activate(
                session: session,
                isFirstTimeSignup: isFirstTimeSignup,
                firstCaseSeed: firstCaseSeed
            )
        }
    }
}

@MainActor
final class ProofKitAuthCoordinator: ObservableObject {
    @Published private(set) var state: ProofKitRootAuthState = .checking

    private let services: ServiceContainer
    private var hasBootstrapped = false
    private var currentScope: ProofKitAuthenticatedScope?

    init(services: ServiceContainer) {
        self.services = services
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await refreshSession()
    }

    func refreshSession() async {
        state = .checking

        guard services.account.isConfigured else {
            state = .signedOut
            return
        }

        do {
            let pendingSeed = ProofKitPendingOnboardingSeedStore.pendingSeed()
            let pendingDisplayName = ProofKitPendingOnboardingSeedStore.pendingProfileDisplayName()
            if let result = try await services.account.currentSession(
                onboardingCategory: pendingSeed?.id,
                onboardingDisplayName: pendingDisplayName
            ) {
                let shouldStartFirstCase = pendingSeed != nil && (
                    result.isNewAccount ||
                    ProofKitPendingOnboardingSeedStore.hasPendingAccountCreationAttempt(matching: result.session.email)
                )
                let firstCaseSeed = shouldStartFirstCase ? pendingSeed : nil

                if !shouldStartFirstCase {
                    ProofKitPendingOnboardingSeedStore.clear()
                }

                state = try .authenticated(makeScope(for: result.session), firstCaseSeed: firstCaseSeed)
            } else {
                state = .signedOut
            }
        } catch {
            state = .configurationError(Self.message(for: error))
        }
    }

    func activate(
        session: ProofKitAccountSession,
        isFirstTimeSignup: Bool,
        firstCaseSeed: ProofKitOnboardingFirstCaseSeed?
    ) async {
        do {
            let scope = try makeScope(for: session)
            let pendingSeed = firstCaseSeed ?? ProofKitPendingOnboardingSeedStore.pendingSeed()
            let shouldStartFirstCase = pendingSeed != nil && (
                firstCaseSeed != nil ||
                isFirstTimeSignup ||
                ProofKitPendingOnboardingSeedStore.hasPendingAccountCreationAttempt(matching: session.email)
            )
            let onboardingSeed = shouldStartFirstCase ? pendingSeed : nil

            if !shouldStartFirstCase {
                ProofKitPendingOnboardingSeedStore.clear()
            }

            state = .authenticated(scope, firstCaseSeed: onboardingSeed)
        } catch {
            state = .configurationError(Self.message(for: error))
        }
    }

    func accountDidSignOut() {
        currentScope = nil
        state = .signedOut
    }

    func handleAuthCallback(_ url: URL) {
        services.account.handleAuthCallback(url)
        Task { await refreshSession() }
    }

    private func makeScope(for session: ProofKitAccountSession) throws -> ProofKitAuthenticatedScope {
        if let currentScope, currentScope.session.id == session.id {
            return currentScope
        }

        let scope = ProofKitAuthenticatedScope(
            session: session,
            services: try services.scoped(to: session),
            modelContainer: try AccountScopedLocalData.modelContainer(for: session)
        )

        currentScope = scope
        return scope
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

struct ProofKitAuthenticatedScope {
    let session: ProofKitAccountSession
    let services: ServiceContainer
    let modelContainer: ModelContainer
}

enum ProofKitRootAuthState {
    case checking
    case signedOut
    case authenticated(ProofKitAuthenticatedScope, firstCaseSeed: ProofKitOnboardingFirstCaseSeed?)
    case configurationError(String)
}
