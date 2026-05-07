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
                ProofKitAuthView(services: services) { session, isFirstTimeSignup in
                    await authCoordinator.activate(session: session, isFirstTimeSignup: isFirstTimeSignup)
                }

            case .authenticated(let scope):
                ContentView {
                    authCoordinator.accountDidSignOut()
                }
                .id(scope.session.id)
                .environment(\.proofKitServices, scope.services)
                .modelContainer(scope.modelContainer)

            case .signupSuccess(let scope):
                ProofKitSignupSuccessView(email: scope.session.email)
                    .id(scope.session.id)

            case .configurationError(let message):
                ProofKitAuthView(services: services, initialErrorMessage: message) { session, isFirstTimeSignup in
                    await authCoordinator.activate(session: session, isFirstTimeSignup: isFirstTimeSignup)
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
}

@MainActor
final class ProofKitAuthCoordinator: ObservableObject {
    @Published private(set) var state: ProofKitRootAuthState = .checking

    private let services: ServiceContainer
    private var hasBootstrapped = false

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
            if let session = try await services.account.currentSession() {
                state = try .authenticated(makeScope(for: session))
            } else {
                state = .signedOut
            }
        } catch {
            state = .configurationError(Self.message(for: error))
        }
    }

    func activate(session: ProofKitAccountSession, isFirstTimeSignup: Bool) async {
        do {
            let scope = try makeScope(for: session)

            if isFirstTimeSignup {
                state = .signupSuccess(scope)
                try? await Task.sleep(for: .seconds(1.15))
            }

            state = .authenticated(scope)
        } catch {
            state = .configurationError(Self.message(for: error))
        }
    }

    func accountDidSignOut() {
        state = .signedOut
    }

    func handleAuthCallback(_ url: URL) {
        services.account.handleAuthCallback(url)
        Task { await refreshSession() }
    }

    private func makeScope(for session: ProofKitAccountSession) throws -> ProofKitAuthenticatedScope {
        ProofKitAuthenticatedScope(
            session: session,
            services: try services.scoped(to: session),
            modelContainer: try AccountScopedLocalData.modelContainer(for: session)
        )
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
    case authenticated(ProofKitAuthenticatedScope)
    case signupSuccess(ProofKitAuthenticatedScope)
    case configurationError(String)
}
