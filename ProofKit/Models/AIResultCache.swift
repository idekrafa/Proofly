import Foundation
import SwiftData

@Model
final class AIResultCache {
    @Attribute(.unique) var id: UUID

    var taskTypeRawValue: String

    // Fingerprints identify extracted text/metadata inputs without storing raw images.
    var inputFingerprint: String
    var sourceTextFingerprint: String?
    var metadataFingerprint: String?

    // AI-generated cache payload. It must not replace original user/OCR/file fields.
    var resultJSON: String
    var modelIdentifier: String?
    var promptVersion: String?
    var userTriggered: Bool

    var createdAt: Date
    var expiresAt: Date?

    var caseFile: CaseFile?
    var evidenceItem: EvidenceItem?

    init(
        id: UUID = UUID(),
        taskType: AITaskType,
        inputFingerprint: String,
        sourceTextFingerprint: String? = nil,
        metadataFingerprint: String? = nil,
        resultJSON: String,
        modelIdentifier: String? = nil,
        promptVersion: String? = nil,
        userTriggered: Bool = true,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        caseFile: CaseFile? = nil,
        evidenceItem: EvidenceItem? = nil
    ) {
        self.id = id
        self.taskTypeRawValue = taskType.rawValue
        self.inputFingerprint = inputFingerprint
        self.sourceTextFingerprint = sourceTextFingerprint
        self.metadataFingerprint = metadataFingerprint
        self.resultJSON = resultJSON
        self.modelIdentifier = modelIdentifier
        self.promptVersion = promptVersion
        self.userTriggered = userTriggered
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.caseFile = caseFile
        self.evidenceItem = evidenceItem
    }

    var taskType: AITaskType {
        get { AITaskType(rawValue: taskTypeRawValue) ?? .summarizeItem }
        set { taskTypeRawValue = newValue.rawValue }
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= .now
    }
}
