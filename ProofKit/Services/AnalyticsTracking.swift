import CryptoKit
import Foundation

protocol AnalyticsTracking {
    var currentUserIDHash: String { get }

    func scoped(to session: ProofKitAccountSession) -> any AnalyticsTracking
    func trackCaseReadinessCalculated(_ payload: CaseReadinessAnalyticsPayload)
}

struct CaseReadinessAnalyticsPayload: Codable, Equatable {
    static let eventName = "case_readiness_calculated"

    let caseIDHash: String
    let userIDHash: String
    let caseType: String
    let readinessScore: Int
    let readinessBucket: String
    let nextStep: String
    let proofItemCount: Int
    let reviewedItemCount: Int
    let unreviewedItemCount: Int
    let timelineItemCount: Int
    let hasTitle: Bool
    let hasDescription: Bool
    let hasExportablePDF: Bool
    let generatedExportCount: Int
    let subscriptionTier: String
    let createdAtAgeDays: Int

    enum CodingKeys: String, CodingKey {
        case caseIDHash = "case_id_hash"
        case userIDHash = "user_id_hash"
        case caseType = "case_type"
        case readinessScore = "readiness_score"
        case readinessBucket = "readiness_bucket"
        case nextStep = "next_step"
        case proofItemCount = "proof_item_count"
        case reviewedItemCount = "reviewed_item_count"
        case unreviewedItemCount = "unreviewed_item_count"
        case timelineItemCount = "timeline_item_count"
        case hasTitle = "has_title"
        case hasDescription = "has_description"
        case hasExportablePDF = "has_exportable_pdf"
        case generatedExportCount = "generated_export_count"
        case subscriptionTier = "subscription_tier"
        case createdAtAgeDays = "created_at_age_days"
    }
}

struct NoOpAnalyticsTracker: AnalyticsTracking {
    let userID: UUID?

    init(userID: UUID? = nil) {
        self.userID = userID
    }

    var currentUserIDHash: String {
        AnalyticsHashing.sha256(userID?.uuidString ?? "anonymous")
    }

    func scoped(to session: ProofKitAccountSession) -> any AnalyticsTracking {
        NoOpAnalyticsTracker(userID: session.userID)
    }

    func trackCaseReadinessCalculated(_ payload: CaseReadinessAnalyticsPayload) {
        // Intentionally empty until a production analytics backend is wired.
        // The payload type only permits hashed identifiers and safe metadata.
    }
}

enum AnalyticsHashing {
    static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
