import Foundation
import SwiftData

@Model
final class CaseFile {
    @Attribute(.unique) var id: UUID

    var caseTypeRawValue: String
    var statusRawValue: String

    // User-authored source-of-truth fields. AI output is stored separately below.
    var userTitle: String
    var userSummary: String
    var userNotes: String
    var thumbnailLocalFilePath: String?

    // AI-generated fields must never replace userTitle/userSummary/userNotes.
    var aiSuggestedTitle: String?
    var aiGeneratedSummary: String?
    var aiGeneratedTimelineJSON: String?

    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \EvidenceItem.caseFile)
    var evidenceItems: [EvidenceItem]

    @Relationship(deleteRule: .cascade, inverse: \ExportPacket.caseFile)
    var exportPackets: [ExportPacket]

    @Relationship(deleteRule: .cascade, inverse: \AIResultCache.caseFile)
    var aiResultCaches: [AIResultCache]

    init(
        id: UUID = UUID(),
        caseType: CaseType = .general,
        status: CaseStatus = .draft,
        userTitle: String,
        userSummary: String = "",
        userNotes: String = "",
        thumbnailLocalFilePath: String? = nil,
        aiSuggestedTitle: String? = nil,
        aiGeneratedSummary: String? = nil,
        aiGeneratedTimelineJSON: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        archivedAt: Date? = nil,
        evidenceItems: [EvidenceItem] = [],
        exportPackets: [ExportPacket] = [],
        aiResultCaches: [AIResultCache] = []
    ) {
        self.id = id
        self.caseTypeRawValue = caseType.rawValue
        self.statusRawValue = status.rawValue
        self.userTitle = userTitle
        self.userSummary = userSummary
        self.userNotes = userNotes
        self.thumbnailLocalFilePath = thumbnailLocalFilePath
        self.aiSuggestedTitle = aiSuggestedTitle
        self.aiGeneratedSummary = aiGeneratedSummary
        self.aiGeneratedTimelineJSON = aiGeneratedTimelineJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.evidenceItems = evidenceItems
        self.exportPackets = exportPackets
        self.aiResultCaches = aiResultCaches
    }

    var caseType: CaseType {
        get { CaseType(rawValue: caseTypeRawValue) ?? .general }
        set { caseTypeRawValue = newValue.rawValue }
    }

    var status: CaseStatus {
        get { CaseStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }

    var sortedEvidenceItems: [EvidenceItem] {
        evidenceItems.sorted { lhs, rhs in
            let lhsDate = lhs.eventDate ?? lhs.createdAt
            let rhsDate = rhs.eventDate ?? rhs.createdAt
            return lhsDate < rhsDate
        }
    }

    var sortedExportPackets: [ExportPacket] {
        exportPackets.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }
}
