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
            String(localized: "\(feature) is not implemented yet.")
        case .unsupportedFileType(let fileType):
            String(localized: "Unsupported file type: \(fileType).")
        case .missingLocalFile(let url):
            String(localized: "Missing local file at \(url.path()).")
        case .localOnlyViolation(let message):
            message
        case .ocrFailed(let message):
            String(localized: "OCR failed: \(message)")
        case .planLimitReached(let message):
            message
        case .revenueCatNotConfigured:
            String(localized: "RevenueCat is not configured for this build.")
        case .revenueCatSDKUnavailable:
            String(localized: "RevenueCat SDK is unavailable in this build.")
        case .revenueCatOfferingUnavailable(let message):
            message
        case .supabaseNotConfigured:
            String(localized: "Supabase is not configured for this build.")
        case .supabaseSDKUnavailable:
            String(localized: "Supabase SDK is unavailable in this build.")
        case .remotePolicyViolation(let message):
            message
        }
    }
}
