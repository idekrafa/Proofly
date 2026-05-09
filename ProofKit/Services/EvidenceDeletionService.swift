import Foundation
import SwiftData

enum EvidenceDeletionService {
    static func deleteFromCase(_ evidenceItem: EvidenceItem, modelContext: ModelContext) throws {
        let linkedAttachments = evidenceItem.sortedAttachments
        let now = Date()

        ProofKitAttachmentPreservationService.preserveOriginalFilesInVault(
            linkedAttachments,
            modelContext: modelContext,
            updatedAt: now
        )

        if let caseFile = evidenceItem.caseFile {
            caseFile.evidenceItems.removeAll { $0.id == evidenceItem.id }
            caseFile.updatedAt = now
        }

        modelContext.delete(evidenceItem)
        try modelContext.save()
    }
}

enum CaseDeletionService {
    static func deleteCase(_ caseFile: CaseFile, modelContext: ModelContext) throws {
        let linkedAttachments = caseFile.evidenceItems.flatMap(\.sortedAttachments)
        let now = Date()

        ProofKitAttachmentPreservationService.preserveOriginalFilesInVault(
            linkedAttachments,
            modelContext: modelContext,
            updatedAt: now
        )

        modelContext.delete(caseFile)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

private enum ProofKitAttachmentPreservationService {
    static func preserveOriginalFilesInVault(
        _ attachments: [Attachment],
        modelContext: ModelContext,
        updatedAt: Date
    ) {
        var preservedPaths = Set<String>()

        for attachment in attachments {
            let originalPath = attachment.localFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !originalPath.isEmpty, preservedPaths.insert(originalPath).inserted else { continue }

            let preservedAttachment = Attachment(
                attachmentType: attachment.attachmentType,
                originalFilename: attachment.originalFilename,
                localFilePath: attachment.localFilePath,
                thumbnailLocalFilePath: attachment.thumbnailLocalFilePath,
                uniformTypeIdentifier: attachment.uniformTypeIdentifier,
                fileSizeBytes: attachment.fileSizeBytes,
                contentHash: attachment.contentHash,
                fileCreatedAt: attachment.fileCreatedAt,
                fileModifiedAt: attachment.fileModifiedAt,
                originalOCRText: attachment.originalOCRText,
                originalOCRTextBlocksJSON: attachment.originalOCRTextBlocksJSON,
                originalOCRLanguageCode: attachment.originalOCRLanguageCode,
                originalOCRConfidence: attachment.originalOCRConfidence,
                originalOCRCompletedAt: attachment.originalOCRCompletedAt,
                importedMetadataJSON: attachment.importedMetadataJSON,
                createdAt: attachment.createdAt,
                updatedAt: updatedAt
            )
            modelContext.insert(preservedAttachment)
        }
    }
}
