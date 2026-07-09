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
                    auth: .init(redirectToURL: configuration.authRedirectURL),
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
            throw ProofKitError.remotePolicyViolation("Sign in before updating your Proofly profile.")
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
                "Check your email to confirm your account, then return to Proofly to open your private workspace."
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

    func signInWithApple(
        _ credential: ProofKitAppleSignInCredential,
        onboardingCategory: String?,
        onboardingDisplayName: String?
    ) async throws -> ProofKitAccountAuthResult {
        #if canImport(Supabase)
        let client = try configuredClient
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: credential.identityToken,
                nonce: credential.nonce
            )
        )
        let displayName = onboardingDisplayName ?? credential.fullName
        let profileRegistration = try? await registerProfile(
            for: session,
            onboardingCategory: onboardingCategory,
            onboardingDisplayName: displayName
        )

        if let userAttributes = Self.appleUserAttributes(
            from: credential,
            displayName: displayName
        ) {
            _ = try? await client.auth.update(user: userAttributes)
        }

        return ProofKitAccountAuthResult(
            session: Self.accountSession(
                from: client.auth.currentSession ?? session,
                profileDisplayName: profileRegistration?.profileDisplayName ?? displayName
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

    func deleteAccount() async throws {
        #if canImport(Supabase)
        let client = try configuredClient
        let response: ProofKitAccountDeletionResponse = try await client.functions.invoke(
            configuredFunctionNames.deleteAccount,
            decoder: Self.remoteJSONDecoder
        )

        guard response.deleted else {
            throw ProofKitError.remotePolicyViolation("Proofly could not confirm the account deletion.")
        }

        // The Edge Function revokes server sessions before deleting the Auth user.
        // Clear this device's stored session as a best-effort local cleanup.
        try? await client.auth.signOut()
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

extension SupabaseInfrastructureService: PDFSignatureValidationServicing {
    func issuePDFSignatureToken(_ request: PDFSignatureTokenIssueRequest) async throws -> PDFSignatureTokenIssueResponse {
        #if canImport(Supabase)
        try Self.validateSignatureIssueRequest(request)

        return try await configuredClient.functions.invoke(
            configuredFunctionNames.createSignatureToken,
            options: FunctionInvokeOptions(body: request),
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func finalizePDFSignatureToken(_ request: PDFSignatureTokenFinalizeRequest) async throws -> PDFSignatureTokenVerifyResponse {
        #if canImport(Supabase)
        guard Self.isSHA256Hex(request.signedPDFSHA256) else {
            throw ProofKitError.remotePolicyViolation("Signed PDF validation requires a SHA-256 file hash.")
        }

        return try await configuredClient.functions.invoke(
            configuredFunctionNames.finalizeSignatureToken,
            options: FunctionInvokeOptions(body: request),
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func verifyPDFSignatureToken(_ request: PDFSignatureTokenVerifyRequest) async throws -> PDFSignatureTokenVerifyResponse {
        #if canImport(Supabase)
        guard !request.validationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofKitError.remotePolicyViolation("Enter a signature token before verifying.")
        }
        if let signedPDFSHA256 = request.signedPDFSHA256, !Self.isSHA256Hex(signedPDFSHA256) {
            throw ProofKitError.remotePolicyViolation("Signed PDF verification requires a SHA-256 file hash.")
        }

        return try await configuredClient.functions.invoke(
            configuredFunctionNames.verifySignatureToken,
            options: FunctionInvokeOptions(body: request),
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }
}

extension SupabaseInfrastructureService: SignatureRequestServicing {
    func createSignatureRequest(_ request: SignatureRequestCreateRequest) async throws -> SignatureRequestCreateResponse {
        #if canImport(Supabase)
        guard Self.isSHA256Hex(request.pdfSHA256) else {
            throw ProofKitError.remotePolicyViolation("Signature requests require a SHA-256 hash of the PDF.")
        }
        guard !request.pdfBase64.isEmpty else {
            throw ProofKitError.remotePolicyViolation("Signature requests require the PDF to share.")
        }
        guard !request.documentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofKitError.remotePolicyViolation("Signature requests require a document title.")
        }

        return try await configuredClient.functions.invoke(
            configuredFunctionNames.createSignatureRequest,
            options: FunctionInvokeOptions(body: request),
            decoder: Self.remoteJSONDecoder
        )
        #else
        throw ProofKitError.supabaseSDKUnavailable
        #endif
    }

    func fetchSignatureRequestStatus(_ request: SignatureRequestStatusRequest) async throws -> SignatureRequestStatusResponse {
        #if canImport(Supabase)
        guard request.requestID != nil || request.caseID != nil else {
            throw ProofKitError.remotePolicyViolation("Signature request lookups need a case or request ID.")
        }

        return try await configuredClient.functions.invoke(
            configuredFunctionNames.signatureRequestStatus,
            options: FunctionInvokeOptions(body: request),
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

    static let remoteJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
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

    static func appleUserAttributes(
        from credential: ProofKitAppleSignInCredential,
        displayName: String?
    ) -> UserAttributes? {
        var data: [String: AnyJSON] = [:]

        if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            data["display_name"] = .string(displayName)
            data["full_name"] = .string(displayName)
            data["name"] = .string(displayName)
        }

        if let givenName = credential.givenName?.trimmingCharacters(in: .whitespacesAndNewlines), !givenName.isEmpty {
            data["given_name"] = .string(givenName)
        }

        if let familyName = credential.familyName?.trimmingCharacters(in: .whitespacesAndNewlines), !familyName.isEmpty {
            data["family_name"] = .string(familyName)
        }

        return data.isEmpty ? nil : UserAttributes(data: data)
    }
    #endif

    static func validateSignatureIssueRequest(_ request: PDFSignatureTokenIssueRequest) throws {
        guard isSHA256Hex(request.signatureImageSHA256) else {
            throw ProofKitError.remotePolicyViolation("Signature validation requires a SHA-256 signature hash.")
        }

        if let sourcePDFSHA256 = request.sourcePDFSHA256, !isSHA256Hex(sourcePDFSHA256) {
            throw ProofKitError.remotePolicyViolation("Signature validation requires a SHA-256 source PDF hash.")
        }

        guard !request.signaturePage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.signaturePlacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofKitError.remotePolicyViolation("Signature validation requires page and placement metadata.")
        }

        guard !request.pdfExportMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProofKitError.remotePolicyViolation("Signature validation requires export mode metadata.")
        }
    }

    static func isSHA256Hex(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count == 64 else { return false }
        let allowedCharacters = Set("0123456789abcdefABCDEF")
        return cleaned.allSatisfy { allowedCharacters.contains($0) }
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
