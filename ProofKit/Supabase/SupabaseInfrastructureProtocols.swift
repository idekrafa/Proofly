import Foundation

enum ProofKitOAuthProvider: String, CaseIterable, Identifiable {
    case apple
    case google

    var id: String { rawValue }
}

protocol AccountServicing {
    var isConfigured: Bool { get }
    func currentSession(onboardingCategory: String?, onboardingDisplayName: String?) async throws -> ProofKitAccountAuthResult?
    func updateProfileDisplayName(_ displayName: String) async throws -> ProofKitAccountSession
    func requestEmailChange(to email: String) async throws
    func signInWithPassword(email: String, password: String) async throws -> ProofKitAccountAuthResult
    func signUpWithPassword(
        email: String,
        password: String,
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitAccountAuthResult
    func signInWithOAuth(
        _ provider: ProofKitOAuthProvider,
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitAccountAuthResult
    func signInWithApple(
        _ credential: ProofKitAppleSignInCredential,
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitAccountAuthResult
    func sendMagicLink(email: String) async throws
    func signOut() async throws
    func deleteAccount() async throws
    func handleAuthCallback(_ url: URL)
}

protocol AICreditTrackingServicing {
    func fetchAICreditBalance() async throws -> AICreditBalance
    func reserveAICredits(_ request: AICreditReservationRequest) async throws -> AICreditReservation
}

protocol AIProxyServicing {
    /// Sends routed AI requests containing task type, compressed text-only
    /// input, a source ID, input hash, and non-file metadata only.
    /// Implementations must not accept raw images, PDFs, attachment bytes, full
    /// files, or local file paths.
    func invokeTextOnlyAI(_ request: AIProxyTextRequest) async throws -> AIProxyTextResponse
    func streamTextOnlyAI(_ request: AIProxyTextRequest) -> AsyncThrowingStream<AIProxyStreamEvent, Error>
}

protocol PurchaseEntitlementServicing {
    func fetchPurchaseEntitlements() async throws -> [PurchaseEntitlementRecord]
}
