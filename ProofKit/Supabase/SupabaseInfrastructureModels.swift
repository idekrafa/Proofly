import Foundation

struct ProofKitAccountSession: Equatable, Identifiable {
    let userID: UUID
    let email: String?
    let accessTokenExpiresAt: Date?

    var id: UUID { userID }
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

struct AICreditReservationRequest: Codable, Equatable {
    let taskType: AITaskType
    let estimatedCredits: Int
    let idempotencyKey: String

    init(
        taskType: AITaskType,
        estimatedCredits: Int,
        idempotencyKey: String = UUID().uuidString
    ) {
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

    init(
        taskType: AITaskType,
        compressedTextInput: String,
        inputHash: String,
        caseID: UUID?,
        evidenceItemID: UUID? = nil,
        evidenceItemIDs: [UUID] = [],
        extractedTextSnippets: [String]? = nil,
        metadata: [String: String] = [:],
        userTriggered: Bool,
        idempotencyKey: String = UUID().uuidString
    ) {
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
    }
}

struct AIProxyTextResponse: Codable, Equatable {
    let resultID: String?
    let outputText: String
    let creditsUsed: Int?
    let remainingCredits: Int?
    let metadata: [String: String]?
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
