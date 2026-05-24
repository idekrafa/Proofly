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
        let coordinator = authCoordinator

        Group {
            switch coordinator.state {
            case .checking:
                ProofKitAuthLaunchView()

            case .signedOut:
                ProofKitAuthView(services: services) { session, isFirstTimeSignup, firstCaseSeed in
                    coordinator.scheduleActivation(
                        session: session,
                        isFirstTimeSignup: isFirstTimeSignup,
                        firstCaseSeed: firstCaseSeed
                    )
                }

            case .authenticated(let scope, let firstCaseSeed):
                ContentView(accountSession: scope.session, firstCaseSeed: firstCaseSeed) {
                    coordinator.accountDidSignOut()
                }
                .id(scope.session.id)
                .environment(\.proofKitServices, scope.services)
                .modelContainer(scope.modelContainer)
                .task(id: scope.session.id) {
                    await scope.services.subscriptions.identifyCustomer(for: scope.session)
                }

            case .configurationError(let message):
                ProofKitAuthView(services: services, initialErrorMessage: message) { session, isFirstTimeSignup, firstCaseSeed in
                    coordinator.scheduleActivation(
                        session: session,
                        isFirstTimeSignup: isFirstTimeSignup,
                        firstCaseSeed: firstCaseSeed
                    )
                }
            }
        }
        .task {
            await coordinator.bootstrapIfNeeded()
        }
        .onOpenURL { url in
            coordinator.handleAuthCallback(url)
        }
    }
}

@MainActor
final class ProofKitAuthCoordinator: ObservableObject {
    @Published private(set) var state: ProofKitRootAuthState = .checking

    private let services: ServiceContainer
    private var hasBootstrapped = false
    private var currentScope: ProofKitAuthenticatedScope?
    private var retiringScopes: [UUID: ProofKitAuthenticatedScope] = [:]
    private var activationTask: Task<Void, Never>?
    private var scopeReleaseTasks: [UUID: Task<Void, Never>] = [:]

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
            await services.subscriptions.resetCustomerForSignedOutState()
            transitionToSignedOut()
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

                await services.subscriptions.identifyCustomer(for: result.session)
                state = try .authenticated(makeScope(for: result.session), firstCaseSeed: firstCaseSeed)
            } else {
                await services.subscriptions.resetCustomerForSignedOutState()
                transitionToSignedOut()
            }
        } catch {
            state = .configurationError(Self.message(for: error))
        }
    }

    func scheduleActivation(
        session: ProofKitAccountSession,
        isFirstTimeSignup: Bool,
        firstCaseSeed: ProofKitOnboardingFirstCaseSeed?
    ) {
        activationTask?.cancel()
        state = .checking

        activationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }

            await self?.activate(
                session: session,
                isFirstTimeSignup: isFirstTimeSignup,
                firstCaseSeed: firstCaseSeed
            )
        }
    }

    private func activate(
        session: ProofKitAccountSession,
        isFirstTimeSignup: Bool,
        firstCaseSeed: ProofKitOnboardingFirstCaseSeed?
    ) async {
        do {
            await services.subscriptions.identifyCustomer(for: session)
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
        activationTask?.cancel()
        activationTask = nil

        Task {
            await services.subscriptions.resetCustomerForSignedOutState()
        }
        transitionToSignedOut()
    }

    func handleAuthCallback(_ url: URL) {
        services.account.handleAuthCallback(url)
        Task { await refreshSession() }
    }

    private func makeScope(for session: ProofKitAccountSession) throws -> ProofKitAuthenticatedScope {
        if let currentScope, currentScope.session.id == session.id {
            if currentScope.session == session {
                return currentScope
            }

            let updatedScope = ProofKitAuthenticatedScope(
                session: session,
                services: currentScope.services,
                modelContainer: currentScope.modelContainer
            )
            self.currentScope = updatedScope
            return updatedScope
        }

        if let retiringScope = retiringScopes[session.id] {
            scopeReleaseTasks[session.id]?.cancel()
            scopeReleaseTasks[session.id] = nil
            retiringScopes[session.id] = nil

            let updatedScope = ProofKitAuthenticatedScope(
                session: session,
                services: retiringScope.services,
                modelContainer: retiringScope.modelContainer
            )
            currentScope = updatedScope
            return updatedScope
        }

        if let currentScope {
            retire(scope: currentScope)
        }

        let scope = ProofKitAuthenticatedScope(
            session: session,
            services: try services.scoped(to: session),
            modelContainer: try AccountScopedLocalData.modelContainer(for: session)
        )

        currentScope = scope
        return scope
    }

    private func transitionToSignedOut() {
        retireCurrentScopeAfterTransition()
        state = .signedOut
    }

    private func retireCurrentScopeAfterTransition() {
        guard let currentScope else {
            return
        }

        retire(scope: currentScope)
        self.currentScope = nil
    }

    private func retire(scope: ProofKitAuthenticatedScope) {
        let sessionID = scope.session.id
        retiringScopes[sessionID] = scope
        scopeReleaseTasks[sessionID]?.cancel()
        scopeReleaseTasks[sessionID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.retiringScopes[sessionID] = nil
            self?.scopeReleaseTasks[sessionID] = nil
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
