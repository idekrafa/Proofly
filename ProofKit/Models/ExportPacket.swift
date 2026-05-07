import Foundation
import SwiftData

@Model
final class ExportPacket {
    @Attribute(.unique) var id: UUID

    // User-selected export fields.
    var userPacketTitle: String
    var userPacketNotes: String

    // AI-generated export draft fields are separate from user-selected fields.
    var aiDraftExecutiveSummary: String?
    var aiDraftTimelineJSON: String?

    // Local export artifact fields. File paths are kept separate and never AI-generated.
    var localPDFFilePath: String?
    var fileSizeBytes: Int64?
    var pageCount: Int?
    var includedEvidenceItemIDsJSON: String
    var exportOptionsJSON: String

    var createdAt: Date
    var exportedAt: Date?

    var caseFile: CaseFile?

    init(
        id: UUID = UUID(),
        userPacketTitle: String,
        userPacketNotes: String = "",
        aiDraftExecutiveSummary: String? = nil,
        aiDraftTimelineJSON: String? = nil,
        localPDFFilePath: String? = nil,
        fileSizeBytes: Int64? = nil,
        pageCount: Int? = nil,
        includedEvidenceItemIDsJSON: String = "[]",
        exportOptionsJSON: String = "{}",
        createdAt: Date = .now,
        exportedAt: Date? = nil,
        caseFile: CaseFile? = nil
    ) {
        self.id = id
        self.userPacketTitle = userPacketTitle
        self.userPacketNotes = userPacketNotes
        self.aiDraftExecutiveSummary = aiDraftExecutiveSummary
        self.aiDraftTimelineJSON = aiDraftTimelineJSON
        self.localPDFFilePath = localPDFFilePath
        self.fileSizeBytes = fileSizeBytes
        self.pageCount = pageCount
        self.includedEvidenceItemIDsJSON = includedEvidenceItemIDsJSON
        self.exportOptionsJSON = exportOptionsJSON
        self.createdAt = createdAt
        self.exportedAt = exportedAt
        self.caseFile = caseFile
    }
}
