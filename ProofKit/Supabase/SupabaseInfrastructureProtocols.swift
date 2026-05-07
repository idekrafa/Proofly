import Foundation

protocol AccountServicing {
    var isConfigured: Bool { get }
    func currentSession() async throws -> ProofKitAccountSession?
    func signInWithPassword(email: String, password: String) async throws -> ProofKitAccountSession
    func sendMagicLink(email: String) async throws
    func signOut() async throws
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
}

protocol PurchaseEntitlementServicing {
    func fetchPurchaseEntitlements() async throws -> [PurchaseEntitlementRecord]
}
