import Foundation

#if canImport(Supabase)
import Supabase
#endif

final class SupabaseInfrastructureService {
    private let configuration: SupabaseConfiguration?

    #if canImport(Supabase)
    private let client: SupabaseClient?
    #endif

    var isConfigured: Bool {
        #if canImport(Supabase)
        configuration?.isConfigured == true
        #else
        false
        #endif
    }

    static func live() -> SupabaseInfrastructureService {
        SupabaseInfrastructureService(configuration: .load())
    }

    init(configuration: SupabaseConfiguration?) {
        self.configuration = configuration

        #if canImport(Supabase)
        if let configuration, configuration.isConfigured {
            client = SupabaseClient(
                supabaseURL: configuration.projectURL,
                supabaseKey: configuration.publishableKey,
                options: SupabaseClientOptions(
                    functions: .init(decoder: Self.remoteJSONDecoder)
                )
            )
        } else {
            client = nil
        }
        #endif
    }
}

extension SupabaseInfrastructureService: AccountServicing {
    func currentSession() async throws -> ProofKitAccountSession? {
        #if canImport(Supabase)
        guard let client else { return nil }
        guard let session = client.auth.currentSession else { return nil }

        return ProofKitAccountSession(
            userID: session.user.id,
            email: session.user.email,
            accessTokenExpiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
        #else
        return nil
        #endif
    }

    func signInWithPassword(email: String, password: String) async throws -> ProofKitAccountSession {
        #if canImport(Supabase)
        let session = try await configuredClient.auth.signIn(email: email, password: password)
        return Self.accountSession(from: session)
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func signUpWithPassword(email: String, password: String) async throws -> ProofKitAccountSession {
        #if canImport(Supabase)
        let response = try await configuredClient.auth.signUp(
            email: email,
            password: password,
            redirectTo: configuration?.authRedirectURL
        )

        guard let session = response.session else {
            throw ProofKitError.remotePolicyViolation(
                "Check your email to confirm your account, then return to ProofKit to open your private workspace."
            )
        }

        return Self.accountSession(from: session)
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func signInWithOAuth(_ provider: ProofKitOAuthProvider) async throws -> ProofKitAccountSession {
        #if canImport(Supabase)
        let session = try await configuredClient.auth.signInWithOAuth(
            provider: provider.supabaseProvider,
            redirectTo: configuration?.authRedirectURL
        )

        return Self.accountSession(from: session)
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func sendMagicLink(email: String) async throws {
        #if canImport(Supabase)
        try await configuredClient.auth.signInWithOTP(
            email: email,
            redirectTo: configuration?.authRedirectURL
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func signOut() async throws {
        #if canImport(Supabase)
        try await configuredClient.auth.signOut()
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func handleAuthCallback(_ url: URL) {
        #if canImport(Supabase)
        client?.handle(url)
        #endif
    }
}

extension SupabaseInfrastructureService: AICreditTrackingServicing {
    func fetchAICreditBalance() async throws -> AICreditBalance {
        #if canImport(Supabase)
        return try await configuredClient.functions.invoke(
            configuredFunctionNames.aiCreditBalance,
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func reserveAICredits(_ request: AICreditReservationRequest) async throws -> AICreditReservation {
        #if canImport(Supabase)
        guard request.estimatedCredits > 0 else {
            throw ProofKitError.remotePolicyViolation("AI credit reservations must request at least one credit.")
        }

        return try await configuredClient.functions.invoke(
            configuredFunctionNames.aiCreditReserve,
            options: FunctionInvokeOptions(body: request),
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }
}

extension SupabaseInfrastructureService: AIProxyServicing {
    func invokeTextOnlyAI(_ request: AIProxyTextRequest) async throws -> AIProxyTextResponse {
        #if canImport(Supabase)
        try Self.validateTextOnlyAIRequest(request)

        return try await configuredClient.functions.invoke(
            configuredFunctionNames.aiProxy,
            options: FunctionInvokeOptions(body: request),
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }
}

extension SupabaseInfrastructureService: PurchaseEntitlementServicing {
    func fetchPurchaseEntitlements() async throws -> [PurchaseEntitlementRecord] {
        #if canImport(Supabase)
        return try await configuredClient.functions.invoke(
            configuredFunctionNames.purchaseEntitlements,
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }
}

private extension SupabaseInfrastructureService {
    #if canImport(Supabase)
    var configuredClient: SupabaseClient {
        get throws {
            guard let client else {
                throw ProofKitError.supabaseNotConfigured
            }

            return client
        }
    }
    #endif

    var configuredFunctionNames: SupabaseFunctionNames {
        get throws {
            guard let functionNames = configuration?.functionNames else {
                throw ProofKitError.supabaseNotConfigured
            }

            return functionNames
        }
    }

    static let remoteJSONDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let string = try? container.decode(String.self) {
                if let date = iso8601WithFractionalSeconds.date(from: string) ?? iso8601.date(from: string) {
                    return date
                }
            }

            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 string or UNIX timestamp."
            )
        }
        return decoder
    }()

    static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    #if canImport(Supabase)
    static func accountSession(from session: Session) -> ProofKitAccountSession {
        ProofKitAccountSession(
            userID: session.user.id,
            email: session.user.email,
            accessTokenExpiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
    }
    #endif

    static func validateTextOnlyAIRequest(_ request: AIProxyTextRequest) throws {
        guard request.userTriggered else {
            throw ProofKitError.localOnlyViolation("AI proxy calls must be explicitly triggered by the user.")
        }

        guard !request.compressedTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofKitError.remotePolicyViolation("AI proxy calls require extracted text. Raw files are not allowed.")
        }

        guard !request.inputHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofKitError.remotePolicyViolation("AI proxy calls require an input hash for caching.")
        }

        guard request.caseID != nil || request.evidenceItemID != nil else {
            throw ProofKitError.remotePolicyViolation("AI proxy calls require a case ID or evidence item ID.")
        }

        guard request.extractedTextSnippets.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ProofKitError.remotePolicyViolation("AI proxy calls require text excerpts. Raw files are not allowed.")
        }

        let forbiddenMetadataKeys = request.metadata.keys.filter { key in
            let normalized = key.lowercased()
            return normalized.contains("path") ||
                normalized.contains("fileurl") ||
                normalized.contains("file_url") ||
                normalized.contains("localfile") ||
                normalized.contains("thumbnail") ||
                normalized.contains("pdf") ||
                normalized.contains("image")
        }

        if !forbiddenMetadataKeys.isEmpty {
            throw ProofKitError.remotePolicyViolation(
                "AI proxy metadata must not include local file paths, image/PDF references, or thumbnail references."
            )
        }

        let forbiddenMetadataValues = request.metadata.values.filter { value in
            let normalized = value.lowercased()
            return normalized.contains("file://") ||
                normalized.contains("/var/mobile/") ||
                normalized.contains("/private/var/") ||
                normalized.contains("/users/") ||
                normalized.contains("/documents/")
        }

        if !forbiddenMetadataValues.isEmpty {
            throw ProofKitError.remotePolicyViolation(
                "AI proxy metadata must not include local file paths or file URLs."
            )
        }
    }
}

#if canImport(Supabase)
private extension ProofKitOAuthProvider {
    var supabaseProvider: Provider {
        switch self {
        case .apple:
            .apple
        case .google:
            .google
        }
    }
}
#endif
