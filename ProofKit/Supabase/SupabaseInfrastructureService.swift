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
    func currentSession(
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitAccountAuthResult? {
        #if canImport(Supabase)
        guard let client else { return nil }
        guard let session = client.auth.currentSession else { return nil }

        let profileRegistration = try? await registerProfile(
            for: session,
            onboardingCategory: onboardingCategory,
            onboardingDisplayName: onboardingDisplayName
        )
        let hasPendingOnboarding = onboardingCategory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let isNewAccount = hasPendingOnboarding && (
            profileRegistration?.isNewProfile ?? Self.isLikelyNewAccount(session.user)
        )

        return ProofKitAccountAuthResult(
            session: Self.accountSession(
                from: session,
                profileDisplayName: profileRegistration?.profileDisplayName ?? onboardingDisplayName
            ),
            isNewAccount: isNewAccount
        )
        #else
        return nil
        #endif
    }

    func updateProfileDisplayName(_ displayName: String) async throws -> ProofKitAccountSession {
        #if canImport(Supabase)
        let normalizedDisplayName = try Self.normalizedDisplayName(displayName)
        let client = try configuredClient
        guard let session = client.auth.currentSession else {
            throw ProofKitError.remotePolicyViolation("Sign in before updating your ProofKit profile.")
        }

        _ = try await registerProfile(
            for: session,
            onboardingCategory: nil,
            onboardingDisplayName: nil
        )

        try await client
            .from("profiles")
            .update(
                ProofKitUpdateProfileDisplayNameRequest(
                    displayName: normalizedDisplayName,
                    updatedAt: .now
                )
            )
            .eq("id", value: session.user.id.uuidString)
            .execute()

        _ = try await client.auth.update(
            user: UserAttributes(
                data: [
                    "display_name": .string(normalizedDisplayName),
                    "full_name": .string(normalizedDisplayName),
                    "name": .string(normalizedDisplayName)
                ]
            )
        )

        let refreshedSession = client.auth.currentSession ?? session
        return Self.accountSession(
            from: refreshedSession,
            profileDisplayName: normalizedDisplayName
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func requestEmailChange(to email: String) async throws {
        #if canImport(Supabase)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            throw ProofKitError.remotePolicyViolation("Enter an email address before saving.")
        }

        _ = try await configuredClient.auth.update(
            user: UserAttributes(email: normalizedEmail),
            redirectTo: configuration?.authRedirectURL
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func signInWithPassword(email: String, password: String) async throws -> ProofKitAccountAuthResult {
        #if canImport(Supabase)
        let session = try await configuredClient.auth.signIn(email: email, password: password)
        let profileRegistration = try? await registerProfile(
            for: session,
            onboardingCategory: nil,
            onboardingDisplayName: nil
        )
        return ProofKitAccountAuthResult(
            session: Self.accountSession(
                from: session,
                profileDisplayName: profileRegistration?.profileDisplayName
            ),
            isNewAccount: false
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func signUpWithPassword(
        email: String,
        password: String,
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitAccountAuthResult {
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

        let profileRegistration = try? await registerProfile(
            for: session,
            onboardingCategory: onboardingCategory,
            onboardingDisplayName: onboardingDisplayName
        )

        return ProofKitAccountAuthResult(
            session: Self.accountSession(
                from: session,
                profileDisplayName: profileRegistration?.profileDisplayName ?? onboardingDisplayName
            ),
            isNewAccount: profileRegistration?.isNewProfile ?? true
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func signInWithOAuth(
        _ provider: ProofKitOAuthProvider,
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitAccountAuthResult {
        #if canImport(Supabase)
        let session = try await configuredClient.auth.signInWithOAuth(
            provider: provider.supabaseProvider,
            redirectTo: configuration?.authRedirectURL
        )
        let profileRegistration = try? await registerProfile(
            for: session,
            onboardingCategory: onboardingCategory,
            onboardingDisplayName: onboardingDisplayName
        )

        return ProofKitAccountAuthResult(
            session: Self.accountSession(
                from: session,
                profileDisplayName: profileRegistration?.profileDisplayName ?? onboardingDisplayName
            ),
            isNewAccount: (profileRegistration?.isNewProfile ?? true) && Self.isLikelyNewAccount(session.user)
        )
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

    func registerProfile(
        for session: Session,
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitProfileRegistrationResult {
        let request = ProofKitRegisterProfileRequest(
            email: session.user.email,
            onboardingCategory: onboardingCategory,
            onboardingDisplayName: onboardingDisplayName
        )

        let results: [ProofKitProfileRegistrationResult] = try await configuredClient
            .rpc("proofkit_register_profile", params: request)
            .execute()
            .value

        guard let result = results.first else {
            throw ProofKitError.remotePolicyViolation("Profile registration returned no result.")
        }

        return result
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
    static func accountSession(
        from session: Session,
        profileDisplayName: String? = nil
    ) -> ProofKitAccountSession {
        let explicitFirstName = metadataString(
            from: session.user,
            keys: [
                "first_name",
                "firstName",
                "given_name",
                "givenName"
            ]
        )
        let metadataDisplayName = metadataString(
            from: session.user,
            keys: [
                "display_name",
                "displayName",
                "full_name",
                "fullName",
                "name",
                "preferred_username",
                "user_name",
                "username"
            ]
        )
        let displayName = UserDisplayName.displayName(profileDisplayName) ?? metadataDisplayName

        return ProofKitAccountSession(
            userID: session.user.id,
            email: session.user.email,
            accessTokenExpiresAt: Date(timeIntervalSince1970: session.expiresAt),
            profileFirstName: UserDisplayName.firstName(
                explicitFirstName: explicitFirstName,
                displayName: displayName
            ),
            profileDisplayName: displayName
        )
    }

    static func metadataString(from user: User, keys: [String]) -> String? {
        for key in keys {
            if let value = metadataString(from: user.userMetadata, key: key) {
                return value
            }
        }

        for identity in user.identities ?? [] {
            for key in keys {
                if let value = metadataString(from: identity.identityData, key: key) {
                    return value
                }
            }
        }

        return nil
    }

    static func metadataString(from metadata: [String: AnyJSON]?, key: String) -> String? {
        guard let rawValue = metadata?[key]?.stringValue else { return nil }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            return value
        }

        return nil
    }

    static func isLikelyNewAccount(_ user: User) -> Bool {
        guard let lastSignInAt = user.lastSignInAt else {
            return true
        }

        return abs(lastSignInAt.timeIntervalSince(user.createdAt)) <= 120
    }

    static func normalizedDisplayName(_ displayName: String) throws -> String {
        let normalized = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            throw ProofKitError.remotePolicyViolation("Enter a name before saving.")
        }

        if normalized.count > 80 {
            return String(normalized.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized
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
            throw ProofKitError.remotePolicyViolation("AI proxy calls require a case ID or proof item ID.")
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

private struct ProofKitRegisterProfileRequest: Encodable {
    let email: String?
    let onboardingCategory: String?
    let onboardingDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case email = "p_email"
        case onboardingCategory = "p_onboarding_category"
        case onboardingDisplayName = "p_display_name"
    }
}

private struct ProofKitUpdateProfileDisplayNameRequest: Encodable {
    let displayName: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case updatedAt = "updated_at"
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
