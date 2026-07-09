import Foundation

struct ProofKitAccountSession: Equatable, Identifiable {
    let userID: UUID
    let email: String?
    let accessTokenExpiresAt: Date?
    let profileFirstName: String?
    let profileDisplayName: String?

    init(
        userID: UUID,
        email: String?,
        accessTokenExpiresAt: Date?,
        profileFirstName: String? = nil,
        profileDisplayName: String? = nil
    ) {
        self.userID = userID
        self.email = email
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.profileFirstName = profileFirstName
        self.profileDisplayName = profileDisplayName
    }

    var id: UUID { userID }
}

struct ProofKitAccountAuthResult: Equatable {
    let session: ProofKitAccountSession
    let isNewAccount: Bool
}

struct ProofKitAppleSignInCredential: Equatable {
    let identityToken: String
    let nonce: String?
    let email: String?
    let givenName: String?
    let middleName: String?
    let familyName: String?

    var fullName: String? {
        let value = [givenName, middleName, familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return value.isEmpty ? nil : value
    }
}

struct ProofKitAccountDeletionResponse: Decodable, Equatable {
    let deleted: Bool
}

struct ProofKitProfileRegistrationResult: Decodable, Equatable {
    let isNewProfile: Bool
    let hasRegisteredBefore: Bool
    let profileDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case isNewProfile = "is_new_profile"
        case hasRegisteredBefore = "has_registered_before"
        case profileDisplayName = "profile_display_name"
    }
}

struct PDFSignatureTokenIssueRequest: Codable, Equatable {
    let caseID: UUID
    let exportID: UUID?
    let sourcePDFSHA256: String?
    let signatureImageSHA256: String
    let signaturePage: String
    let signaturePlacement: String
    let signedAt: String
    let appVersion: String
    let pdfExportMode: String
    let includeStatementPlaceholder: Bool
}

struct PDFSignatureTokenIssueResponse: Codable, Equatable {
    let validationToken: String
    let encryptedManifest: String
    let manifestSignature: String
    let manifestSHA256: String
    let algorithm: String
    let keyVersion: String
    let issuedAt: Date
    let verificationURL: URL?
}

struct PDFSignatureTokenFinalizeRequest: Codable, Equatable {
    let validationToken: String
    let signedPDFSHA256: String
    let exportID: UUID
}

struct PDFSignatureTokenVerifyRequest: Codable, Equatable {
    let validationToken: String
    let signedPDFSHA256: String?
}

struct PDFSignatureTokenVerifyResponse: Codable, Equatable {
    let valid: Bool
    let status: String
    let validationToken: String
    let issuedAt: Date?
    let signedAt: Date?
    let finalizedAt: Date?
    let algorithm: String?
    let keyVersion: String?
    let reason: String?
}

struct SignatureRequestCreateRequest: Codable, Equatable {
    let caseID: UUID
    let exportID: UUID?
    let pdfBase64: String
    let pdfSHA256: String
    let documentTitle: String
    let requesterName: String?
    let message: String?
    let signaturePage: String
    let signaturePlacement: String
    let appVersion: String
    let expiresInDays: Int
}

struct SignatureRequestCreateResponse: Codable, Equatable {
    let requestID: UUID
    let status: String
    let shareURL: URL
    let expiresAt: Date
}

enum SignatureRequestState: String, Codable, Equatable {
    case none
    case pending
    case signed
    case cancelled
    case expired
}

struct SignatureRequestStatusRequest: Codable, Equatable {
    let requestID: UUID?
    let caseID: UUID?
    let cancel: Bool
    let includeSignatureImage: Bool

    init(
        requestID: UUID? = nil,
        caseID: UUID? = nil,
        cancel: Bool = false,
        includeSignatureImage: Bool = true
    ) {
        self.requestID = requestID
        self.caseID = caseID
        self.cancel = cancel
        self.includeSignatureImage = includeSignatureImage
    }
}

struct SignatureRequestStatusResponse: Codable, Equatable {
    let status: SignatureRequestState
    let requestID: UUID?
    let caseID: UUID?
    let exportID: UUID?
    let documentTitle: String?
    let shareURL: URL?
    let expiresAt: Date?
    let createdAt: Date?
    let signaturePage: String?
    let signaturePlacement: String?
    let pdfSHA256: String?
    let signerName: String?
    let signedAt: Date?
    let signatureImageSHA256: String?
    let signatureImageBase64: String?
}

struct PurchaseEntitlementRecord: Codable, Equatable, Identifiable {
    let id: String
    let productID: String
    let entitlement: String
    let isActive: Bool
    let source: String
    let expiresAt: Date?
    let updatedAt: Date?
}
