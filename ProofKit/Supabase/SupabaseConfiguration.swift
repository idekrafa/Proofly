import Foundation

/// Runtime Supabase configuration for account, AI credit, AI proxy, and
/// purchase-entitlement infrastructure only.
///
/// Values must be provided by build settings / Info.plist / environment. Do not
/// hardcode project URLs, publishable keys, or secrets in source.
struct SupabaseConfiguration: Equatable {
    let projectURL: URL
    let publishableKey: String
    let authRedirectURL: URL?
    let functionNames: SupabaseFunctionNames

    var isConfigured: Bool {
        !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SupabaseConfiguration? {
        guard let projectURL = projectURL(bundle: bundle, environment: environment),
        let publishableKey = firstNonEmptyString(
            keys: [
                "PROOFKIT_SUPABASE_PUBLISHABLE_KEY",
                "SUPABASE_PUBLISHABLE_KEY",
                "SUPABASE_ANON_KEY"
            ],
            bundle: bundle,
            environment: environment
        ) else {
            return nil
        }

        let redirectURL = firstNonEmptyString(
            keys: [
                "PROOFKIT_SUPABASE_AUTH_REDIRECT_URL",
                "SUPABASE_AUTH_REDIRECT_URL"
            ],
            bundle: bundle,
            environment: environment
        ).flatMap(URL.init(string:))

        return SupabaseConfiguration(
            projectURL: projectURL,
            publishableKey: publishableKey,
            authRedirectURL: redirectURL,
            functionNames: .load(bundle: bundle, environment: environment)
        )
    }

    private static func firstNonEmptyString(
        keys: [String],
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        for key in keys {
            if let value = environment[key]?.proofKitNonEmptyConfigurationValue {
                return value
            }

            if let value = bundle.object(forInfoDictionaryKey: key) as? String,
               let cleaned = value.proofKitNonEmptyConfigurationValue {
                return cleaned
            }
        }

        return nil
    }

    private static func projectURL(
        bundle: Bundle,
        environment: [String: String]
    ) -> URL? {
        if let projectURLString = firstNonEmptyString(
            keys: [
                "PROOFKIT_SUPABASE_URL",
                "SUPABASE_URL"
            ],
            bundle: bundle,
            environment: environment
        ),
        let projectURL = URL(string: projectURLString) {
            return projectURL
        }

        guard let projectRef = firstNonEmptyString(
            keys: [
                "PROOFKIT_SUPABASE_PROJECT_REF",
                "SUPABASE_PROJECT_REF"
            ],
            bundle: bundle,
            environment: environment
        ) else {
            return nil
        }

        return URL(string: "https://\(projectRef).supabase.co")
    }
}

struct SupabaseFunctionNames: Equatable {
    let aiCreditBalance: String
    let aiCreditReserve: String
    let aiProxy: String
    let purchaseEntitlements: String
    let deleteAccount: String
    let createSignatureToken: String
    let finalizeSignatureToken: String
    let verifySignatureToken: String
    let createSignatureRequest: String
    let signatureRequestStatus: String

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SupabaseFunctionNames {
        SupabaseFunctionNames(
            aiCreditBalance: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_AI_CREDIT_BALANCE",
                defaultValue: "ai-credit-balance",
                bundle: bundle,
                environment: environment
            ),
            aiCreditReserve: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_AI_CREDIT_RESERVE",
                defaultValue: "ai-credit-reserve",
                bundle: bundle,
                environment: environment
            ),
            aiProxy: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_AI_PROXY",
                defaultValue: "ai-proxy",
                bundle: bundle,
                environment: environment
            ),
            purchaseEntitlements: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_PURCHASE_ENTITLEMENTS",
                defaultValue: "purchase-entitlements",
                bundle: bundle,
                environment: environment
            ),
            deleteAccount: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_DELETE_ACCOUNT",
                defaultValue: "delete-account",
                bundle: bundle,
                environment: environment
            ),
            createSignatureToken: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_CREATE_SIGNATURE_TOKEN",
                defaultValue: "create-signature-token",
                bundle: bundle,
                environment: environment
            ),
            finalizeSignatureToken: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_FINALIZE_SIGNATURE_TOKEN",
                defaultValue: "finalize-signature-token",
                bundle: bundle,
                environment: environment
            ),
            verifySignatureToken: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_VERIFY_SIGNATURE_TOKEN",
                defaultValue: "verify-signature-token",
                bundle: bundle,
                environment: environment
            ),
            createSignatureRequest: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_CREATE_SIGNATURE_REQUEST",
                defaultValue: "create-signature-request",
                bundle: bundle,
                environment: environment
            ),
            signatureRequestStatus: configuredFunctionName(
                key: "PROOFKIT_SUPABASE_FN_SIGNATURE_REQUEST_STATUS",
                defaultValue: "signature-request-status",
                bundle: bundle,
                environment: environment
            )
        )
    }

    private static func configuredFunctionName(
        key: String,
        defaultValue: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> String {
        if let value = environment[key]?.proofKitNonEmptyConfigurationValue {
            return value
        }

        if let value = bundle.object(forInfoDictionaryKey: key) as? String,
           let cleaned = value.proofKitNonEmptyConfigurationValue {
            return cleaned
        }

        return defaultValue
    }
}

private extension String {
    var proofKitNonEmptyConfigurationValue: String? {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.contains("$(") else { return nil }
        return cleaned
    }
}
