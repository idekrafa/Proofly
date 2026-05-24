import Foundation
import SwiftData

enum AIRequestQueueStatus: String, Codable, CaseIterable {
    case queued
    case running
    case failed
    case waitingForCredits
    case completed
    case cancelled
}

@Model
final class AIRequestQueueItem {
    @Attribute(.unique) var id: UUID

    var actionKindRawValue: String
    var taskTypeRawValue: String
    var caseID: UUID?
    var evidenceItemID: UUID?
    var creditCostQuote: Int?
    var idempotencyKey: String
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var cancelledAt: Date?
    var nextAttemptAt: Date?
    var attemptCount: Int
    var lastErrorMessage: String?

    init(
        id: UUID = UUID(),
        actionKind: AIActionKind,
        taskType: AITaskType? = nil,
        caseID: UUID?,
        evidenceItemID: UUID? = nil,
        creditCostQuote: Int? = nil,
        idempotencyKey: String = UUID().uuidString,
        status: AIRequestQueueStatus = .queued,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil,
        nextAttemptAt: Date? = nil,
        attemptCount: Int = 0,
        lastErrorMessage: String? = nil
    ) {
        self.id = id
        self.actionKindRawValue = actionKind.rawValue
        self.taskTypeRawValue = (taskType ?? actionKind.taskType).rawValue
        self.caseID = caseID
        self.evidenceItemID = evidenceItemID
        self.creditCostQuote = creditCostQuote
        self.idempotencyKey = idempotencyKey
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.nextAttemptAt = nextAttemptAt
        self.attemptCount = attemptCount
        self.lastErrorMessage = lastErrorMessage
    }

    var actionKind: AIActionKind {
        get { AIActionKind(rawValue: actionKindRawValue) ?? .timelineSummary }
        set {
            actionKindRawValue = newValue.rawValue
            taskTypeRawValue = newValue.taskType.rawValue
        }
    }

    var taskType: AITaskType {
        get { AITaskType(rawValue: taskTypeRawValue) ?? actionKind.taskType }
        set { taskTypeRawValue = newValue.rawValue }
    }

    var status: AIRequestQueueStatus {
        get { AIRequestQueueStatus(rawValue: statusRawValue) ?? .queued }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var displayTitle: String {
        actionKind.displayName
    }
}
