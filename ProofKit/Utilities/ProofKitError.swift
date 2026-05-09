import Foundation

enum ProofKitError: LocalizedError {
    case notImplemented(String)
    case unsupportedFileType(String)
    case missingLocalFile(URL)
    case localOnlyViolation(String)
    case ocrFailed(String)
    case planLimitReached(String)
    case revenueCatNotConfigured
    case revenueCatSDKUnavailable
    case revenueCatOfferingUnavailable(String)
    case supabaseNotConfigured
    case supabaseSDKUnavailable
    case remotePolicyViolation(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let feature):
            "\(feature) is not implemented yet."
        case .unsupportedFileType(let fileType):
            "Unsupported file type: \(fileType)."
        case .missingLocalFile(let url):
            "Missing local file at \(url.path())."
        case .localOnlyViolation(let message):
            message
        case .ocrFailed(let message):
            "OCR failed: \(message)"
        case .planLimitReached(let message):
            message
        case .revenueCatNotConfigured:
            "RevenueCat is not configured for this build."
        case .revenueCatSDKUnavailable:
            "RevenueCat SDK is unavailable in this build."
        case .revenueCatOfferingUnavailable(let message):
            message
        case .supabaseNotConfigured:
            "Supabase is not configured for this build."
        case .supabaseSDKUnavailable:
            "Supabase SDK is unavailable in this build."
        case .remotePolicyViolation(let message):
            message
        }
    }
}
