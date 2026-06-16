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

struct AICreditBalance: Codable, Equatable {
    let availableCredits: Int
    let reservedCredits: Int
    let includedMonthlyCredits: Int?
    let renewsAt: Date?
    let updatedAt: Date?

    init(
        availableCredits: Int,
        reservedCredits: Int = 0,
        includedMonthlyCredits: Int? = nil,
        renewsAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.availableCredits = availableCredits
        self.reservedCredits = reservedCredits
        self.includedMonthlyCredits = includedMonthlyCredits
        self.renewsAt = renewsAt
        self.updatedAt = updatedAt
    }
}

enum AIActionKind: String, CaseIterable, Codable, Identifiable {
    case timelineSummary = "timeline_summary"
    case packetPolish = "packet_polish"
    case deepReview = "deep_review"
    case askAIShort = "ask_ai_short"
    case askAICase = "ask_ai_case"
    case rewriteNote = "rewrite_note"

    var id: String { rawValue }

    init(taskType: AITaskType) {
        switch taskType {
        case .rewriteNote:
            self = .rewriteNote
        case .summarizeTimeline:
            self = .timelineSummary
        case .finalCaseNarrative:
            self = .packetPolish
        case .summarizeItem, .suggestTitle:
            self = .askAIShort
        case .classifyEvidence:
            self = .deepReview
        }
    }

    var displayName: String {
        switch self {
        case .timelineSummary:
            "Timeline Summary"
        case .packetPolish:
            "Packet Polish"
        case .deepReview:
            "Deep Review"
        case .askAIShort:
            "Ask AI"
        case .askAICase:
            "Ask AI with Case Context"
        case .rewriteNote:
            "Clean Up Note"
        }
    }

    var defaultCreditCost: Int {
        switch self {
        case .timelineSummary:
            2
        case .packetPolish:
            4
        case .deepReview:
            10
        case .askAIShort:
            1
        case .askAICase:
            3
        case .rewriteNote:
            1
        }
    }

    var estimatedWaitMessage: String {
        switch self {
        case .timelineSummary:
            "Usually under a minute."
        case .packetPolish:
            "May take about a minute."
        case .deepReview:
            "May take a few minutes for large timelines."
        case .askAIShort, .askAICase, .rewriteNote:
            "Usually under a minute."
        }
    }

    var taskType: AITaskType {
        switch self {
        case .rewriteNote:
            .rewriteNote
        case .timelineSummary:
            .summarizeTimeline
        case .packetPolish:
            .finalCaseNarrative
        case .deepReview:
            .classifyEvidence
        case .askAIShort, .askAICase:
            .summarizeItem
        }
    }
}

struct AIUsageQuote: Codable, Equatable {
    let feature: AIActionKind
    let creditCost: Int
    let creditsRemainingBefore: Int
    let creditsRemainingAfter: Int
    let estimatedWaitMessage: String
}

struct AICreditReservationRequest: Codable, Equatable {
    let feature: AIActionKind
    let taskType: AITaskType
    let estimatedCredits: Int
    let idempotencyKey: String

    init(
        taskType: AITaskType,
        feature: AIActionKind? = nil,
        estimatedCredits: Int,
        idempotencyKey: String = UUID().uuidString
    ) {
        self.feature = feature ?? AIActionKind(taskType: taskType)
        self.taskType = taskType
        self.estimatedCredits = estimatedCredits
        self.idempotencyKey = idempotencyKey
    }
}

struct AICreditReservation: Codable, Equatable {
    let reservationID: String
    let creditsReserved: Int
    let remainingCredits: Int
    let expiresAt: Date?
}

struct AIProxyTextRequest: Codable, Equatable {
    let feature: AIActionKind
    let taskType: AITaskType
    let compressedTextInput: String
    let inputHash: String
    let caseID: UUID?
    let evidenceItemID: UUID?
    let evidenceItemIDs: [UUID]
    let extractedTextSnippets: [String]
    let metadata: [String: String]
    let userTriggered: Bool
    let idempotencyKey: String
    let stream: Bool?

    init(
        taskType: AITaskType,
        feature: AIActionKind? = nil,
        compressedTextInput: String,
        inputHash: String,
        caseID: UUID?,
        evidenceItemID: UUID? = nil,
        evidenceItemIDs: [UUID] = [],
        extractedTextSnippets: [String]? = nil,
        metadata: [String: String] = [:],
        userTriggered: Bool,
        idempotencyKey: String = UUID().uuidString,
        stream: Bool? = nil
    ) {
        self.feature = feature ?? AIActionKind(taskType: taskType)
        self.taskType = taskType
        self.compressedTextInput = compressedTextInput
        self.inputHash = inputHash
        self.caseID = caseID
        self.evidenceItemID = evidenceItemID
        self.evidenceItemIDs = evidenceItemIDs
        self.extractedTextSnippets = extractedTextSnippets ?? [compressedTextInput]
        self.metadata = metadata
        self.userTriggered = userTriggered
        self.idempotencyKey = idempotencyKey
        self.stream = stream
    }
}

struct AIProxyTextResponse: Codable, Equatable {
    let resultID: String?
    let outputText: String
    let creditsUsed: Int?
    let remainingCredits: Int?
    let metadata: [String: String]?
}

struct AIProxyStreamStart: Codable, Equatable {
    let resultID: String?
    let creditsUsed: Int?
    let remainingCredits: Int?
    let metadata: [String: String]?
}

enum AIProxyStreamEvent: Equatable {
    case started(AIProxyStreamStart)
    case textDelta(String)
    case completed(AIProxyTextResponse)
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
