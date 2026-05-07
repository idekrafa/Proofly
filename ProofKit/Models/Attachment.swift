import Foundation
import SwiftData

@Model
final class Attachment {
    @Attribute(.unique) var id: UUID

    var attachmentTypeRawValue: String

    // Local source-of-truth file fields. These must not be replaced by AI output.
    var originalFilename: String
    var localFilePath: String
    var thumbnailLocalFilePath: String?
    var uniformTypeIdentifier: String?
    var fileSizeBytes: Int64?
    var contentHash: String?
    var fileCreatedAt: Date?
    var fileModifiedAt: Date?

    // OCR source-of-truth fields for this specific local attachment.
    var originalOCRText: String
    var originalOCRTextBlocksJSON: String = "[]"
    var originalOCRLanguageCode: String?
    var originalOCRConfidence: Double?
    var originalOCRCompletedAt: Date?

    // Non-AI import metadata stored as JSON so the model stays local and schema-stable.
    var importedMetadataJSON: String

    var createdAt: Date
    var updatedAt: Date

    var evidenceItem: EvidenceItem?

    init(
        id: UUID = UUID(),
        attachmentType: AttachmentType,
        originalFilename: String,
        localFilePath: String,
        thumbnailLocalFilePath: String? = nil,
        uniformTypeIdentifier: String? = nil,
        fileSizeBytes: Int64? = nil,
        contentHash: String? = nil,
        fileCreatedAt: Date? = nil,
        fileModifiedAt: Date? = nil,
        originalOCRText: String = "",
        originalOCRTextBlocksJSON: String = "[]",
        originalOCRLanguageCode: String? = nil,
        originalOCRConfidence: Double? = nil,
        originalOCRCompletedAt: Date? = nil,
        importedMetadataJSON: String = "{}",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        evidenceItem: EvidenceItem? = nil
    ) {
        self.id = id
        self.attachmentTypeRawValue = attachmentType.rawValue
        self.originalFilename = originalFilename
        self.localFilePath = localFilePath
        self.thumbnailLocalFilePath = thumbnailLocalFilePath
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.fileSizeBytes = fileSizeBytes
        self.contentHash = contentHash
        self.fileCreatedAt = fileCreatedAt
        self.fileModifiedAt = fileModifiedAt
        self.originalOCRText = originalOCRText
        self.originalOCRTextBlocksJSON = originalOCRTextBlocksJSON
        self.originalOCRLanguageCode = originalOCRLanguageCode
        self.originalOCRConfidence = originalOCRConfidence
        self.originalOCRCompletedAt = originalOCRCompletedAt
        self.importedMetadataJSON = importedMetadataJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.evidenceItem = evidenceItem
    }

    var attachmentType: AttachmentType {
        get { AttachmentType(rawValue: attachmentTypeRawValue) ?? .other }
        set { attachmentTypeRawValue = newValue.rawValue }
    }
}
