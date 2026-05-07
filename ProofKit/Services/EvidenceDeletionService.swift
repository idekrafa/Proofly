import Foundation
import SwiftData

enum EvidenceDeletionService {
    static func deleteFromCase(_ evidenceItem: EvidenceItem, modelContext: ModelContext) throws {
        let linkedAttachments = evidenceItem.sortedAttachments
        let now = Date()

        try deleteLocalAttachmentFiles(linkedAttachments)

        if let caseFile = evidenceItem.caseFile {
            caseFile.evidenceItems.removeAll { $0.id == evidenceItem.id }
            caseFile.updatedAt = now
        }

        modelContext.delete(evidenceItem)
        try modelContext.save()
    }

    private static func deleteLocalAttachmentFiles(_ attachments: [Attachment]) throws {
        var localPaths = Set<String>()

        for attachment in attachments {
            let originalPath = attachment.localFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !originalPath.isEmpty {
                localPaths.insert(originalPath)
            }

            if let thumbnailPath = attachment.thumbnailLocalFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thumbnailPath.isEmpty {
                localPaths.insert(thumbnailPath)
            }
        }

        let fileManager = FileManager.default
        for path in localPaths {
            guard fileManager.fileExists(atPath: path) else { continue }
            try fileManager.removeItem(at: URL(filePath: path))
        }
    }
}
