import Combine
import Foundation
import SwiftData

struct AIQueueSummary: Equatable {
    var queuedCount: Int = 0
    var runningCount: Int = 0
    var waitingForCreditsCount: Int = 0
    var failedCount: Int = 0

    var pendingCount: Int {
        queuedCount + runningCount + waitingForCreditsCount
    }

    var hasPendingWork: Bool {
        pendingCount > 0
    }
}

@MainActor
final class AIRequestQueueService: ObservableObject {
    @Published private(set) var summary = AIQueueSummary()
    @Published private(set) var isProcessing = false
    @Published private(set) var lastQueueMessage: String?

    private let aiCredits: any AICreditTrackingServicing
    private let aiActions: any AIActionServicing
    private let aiRouter: any AITaskRoutingServicing
    private let serviceHealth: ServiceHealthMonitor

    init(
        aiCredits: any AICreditTrackingServicing,
        aiActions: any AIActionServicing,
        aiRouter: any AITaskRoutingServicing,
        serviceHealth: ServiceHealthMonitor
    ) {
        self.aiCredits = aiCredits
        self.aiActions = aiActions
        self.aiRouter = aiRouter
        self.serviceHealth = serviceHealth
    }

    @discardableResult
    func enqueue(
        _ actionKind: AIActionKind,
        caseFile: CaseFile,
        quote: AIUsageQuote?,
        in modelContext: ModelContext
    ) throws -> AIRequestQueueItem {
        let item = AIRequestQueueItem(
            actionKind: actionKind,
            caseID: caseFile.id,
            creditCostQuote: quote?.creditCost ?? actionKind.defaultCreditCost
        )
        modelContext.insert(item)
        try modelContext.save()
        refreshSummary(in: modelContext)
        lastQueueMessage = String(localized: "\(actionKind.displayName) will run when connection returns and credits are available.")
        return item
    }

    @discardableResult
    func enqueueCleanUpNote(
        for evidenceItem: EvidenceItem,
        creditCostQuote: Int? = 1,
        in modelContext: ModelContext
    ) throws -> AIRequestQueueItem {
        let item = AIRequestQueueItem(
            actionKind: .rewriteNote,
            caseID: evidenceItem.caseFile?.id,
            evidenceItemID: evidenceItem.id,
            creditCostQuote: creditCostQuote
        )
        modelContext.insert(item)
        try modelContext.save()
        refreshSummary(in: modelContext)
        lastQueueMessage = String(localized: "Clean Up Note will run when connection returns and credits are available.")
        return item
    }

    func cancel(_ item: AIRequestQueueItem, in modelContext: ModelContext) {
        guard item.status == .queued || item.status == .waitingForCredits || item.status == .failed else { return }
        item.status = .cancelled
        item.cancelledAt = .now
        try? modelContext.save()
        refreshSummary(in: modelContext)
    }

    func refreshSummary(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<AIRequestQueueItem>()
        guard let items = try? modelContext.fetch(descriptor) else {
            summary = AIQueueSummary()
            return
        }

        summary = AIQueueSummary(
            queuedCount: items.filter { $0.status == .queued }.count,
            runningCount: items.filter { $0.status == .running }.count,
            waitingForCreditsCount: items.filter { $0.status == .waitingForCredits }.count,
            failedCount: items.filter { $0.status == .failed }.count
        )
    }

    func resumeWaitingForCredits(in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<AIRequestQueueItem>(
            predicate: #Predicate<AIRequestQueueItem> { item in
                item.statusRawValue == "waitingForCredits"
            }
        )
        guard let items = try? modelContext.fetch(descriptor) else { return }
        for item in items {
            item.status = .queued
            item.lastErrorMessage = nil
        }
        try? modelContext.save()
        refreshSummary(in: modelContext)
    }

    func processPendingItems(in modelContext: ModelContext) async {
        guard !isProcessing else { return }
        refreshSummary(in: modelContext)
        guard summary.queuedCount > 0 else { return }

        if serviceHealth.snapshot.state == .offline {
            lastQueueMessage = String(localized: "AI will run when connection returns and credits are available.")
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
            refreshSummary(in: modelContext)
        }

        while let item = nextQueuedItem(in: modelContext) {
            if let nextAttemptAt = item.nextAttemptAt, nextAttemptAt > .now {
                break
            }

            let cost = item.creditCostQuote ?? item.actionKind.defaultCreditCost

            do {
                let balance = try await aiCredits.fetchAICreditBalance()
                serviceHealth.markHealthy()

                guard balance.availableCredits >= cost else {
                    markQueueWaitingForCredits(
                        from: item,
                        availableCredits: balance.availableCredits,
                        requiredCredits: cost,
                        in: modelContext
                    )
                    break
                }

                try await run(item, in: modelContext)
            } catch {
                serviceHealth.record(error, context: item.actionKind == .rewriteNote ? .aiProvider : .supabaseEdgeFunction)
                if ServiceHealthMonitor.isServiceAvailabilityError(error) {
                    pause(item, error: error, in: modelContext)
                    break
                } else {
                    fail(item, error: error, in: modelContext)
                }
            }
        }
    }

    private func nextQueuedItem(in modelContext: ModelContext) -> AIRequestQueueItem? {
        var descriptor = FetchDescriptor<AIRequestQueueItem>(
            predicate: #Predicate<AIRequestQueueItem> { item in
                item.statusRawValue == "queued"
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func run(_ item: AIRequestQueueItem, in modelContext: ModelContext) async throws {
        item.status = .running
        item.startedAt = .now
        item.attemptCount += 1
        item.lastErrorMessage = nil
        try modelContext.save()
        refreshSummary(in: modelContext)

        switch item.actionKind {
        case .timelineSummary, .packetPolish:
            guard let caseFile = try fetchCase(id: item.caseID, in: modelContext) else {
                throw ProofKitError.remotePolicyViolation(String(localized: "The case for this queued AI request was deleted."))
            }
            _ = try await aiActions.runQueuedAction(
                item.actionKind,
                for: caseFile,
                in: modelContext,
                userTriggered: true,
                idempotencyKey: item.idempotencyKey
            )

        case .rewriteNote:
            guard let evidenceItem = try fetchEvidenceItem(id: item.evidenceItemID, in: modelContext) else {
                throw ProofKitError.remotePolicyViolation(String(localized: "The proof item for this queued AI request was deleted."))
            }
            let userNote = evidenceItem.userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !userNote.isEmpty else {
                throw ProofKitError.remotePolicyViolation(String(localized: "The note for this queued cleanup is empty."))
            }

            let result = try await aiRouter.cleanUpNote(
                for: evidenceItem,
                userNote: userNote,
                in: modelContext,
                userTriggered: true,
                idempotencyKey: item.idempotencyKey
            )
            let rewrittenNote = result.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewrittenNote.isEmpty else {
                throw ProofKitError.remotePolicyViolation(String(localized: "The AI proxy returned an empty rewrite."))
            }

            evidenceItem.userCleanedNote = rewrittenNote
            evidenceItem.updatedAt = .now
            evidenceItem.caseFile?.updatedAt = .now

        case .deepReview, .askAIShort, .askAICase:
            throw ProofKitError.notImplemented(item.actionKind.displayName)
        }

        item.status = .completed
        item.completedAt = .now
        item.lastErrorMessage = nil
        try modelContext.save()
        lastQueueMessage = String(localized: "\(item.displayTitle) completed.")
        refreshSummary(in: modelContext)
    }

    private func fetchCase(id: UUID?, in modelContext: ModelContext) throws -> CaseFile? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<CaseFile>(
            predicate: #Predicate<CaseFile> { caseFile in
                caseFile.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchEvidenceItem(id: UUID?, in modelContext: ModelContext) throws -> EvidenceItem? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<EvidenceItem>(
            predicate: #Predicate<EvidenceItem> { evidenceItem in
                evidenceItem.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func markQueueWaitingForCredits(
        from item: AIRequestQueueItem,
        availableCredits: Int,
        requiredCredits: Int,
        in modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<AIRequestQueueItem>(
            predicate: #Predicate<AIRequestQueueItem> { queuedItem in
                queuedItem.statusRawValue == "queued"
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        var items = (try? modelContext.fetch(descriptor)) ?? []
        if !items.contains(where: { $0.id == item.id }) {
            items.insert(item, at: 0)
        }
        for queuedItem in items {
            queuedItem.status = .waitingForCredits
            queuedItem.lastErrorMessage = String(localized: "\(queuedItem.displayTitle) needs \(queuedItem.creditCostQuote ?? queuedItem.actionKind.defaultCreditCost) AI credit(s). You have \(availableCredits) available.")
        }
        try? modelContext.save()
        lastQueueMessage = String(localized: "AI queue is waiting for credits. \(item.displayTitle) needs \(requiredCredits), but \(availableCredits) are available.")
        refreshSummary(in: modelContext)
    }

    private func pause(_ item: AIRequestQueueItem, error: Error, in modelContext: ModelContext) {
        item.status = .queued
        item.nextAttemptAt = Date().addingTimeInterval(min(300, Double(max(1, item.attemptCount)) * 30))
        item.lastErrorMessage = Self.message(for: error)
        try? modelContext.save()
        lastQueueMessage = String(localized: "AI queue paused. It will retry when services return.")
        refreshSummary(in: modelContext)
    }

    private func fail(_ item: AIRequestQueueItem, error: Error, in modelContext: ModelContext) {
        item.status = .failed
        item.lastErrorMessage = Self.message(for: error)
        try? modelContext.save()
        lastQueueMessage = String(localized: "\(item.displayTitle) needs attention before it can run.")
        refreshSummary(in: modelContext)
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
