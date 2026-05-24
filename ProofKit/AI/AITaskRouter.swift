import CryptoKit
import Foundation
import SwiftData

struct AITaskRouteResult: Equatable {
    let taskType: AITaskType
    let caseID: UUID?
    let evidenceItemID: UUID?
    let inputHash: String
    let compressedTextInput: String
    let outputText: String
    let responseMetadata: [String: String]
    let creditsUsed: Int?
    let remainingCredits: Int?
    let cacheID: UUID?
    let wasCacheHit: Bool
}

@MainActor
protocol AITaskRoutingServicing {
    func route(
        _ taskType: AITaskType,
        for evidenceItem: EvidenceItem,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String?
    ) async throws -> AITaskRouteResult

    func route(
        _ taskType: AITaskType,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String?
    ) async throws -> AITaskRouteResult

    func routeStreaming(
        _ taskType: AITaskType,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String?,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> AITaskRouteResult

    func cleanUpNote(
        for evidenceItem: EvidenceItem,
        userNote: String,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String?
    ) async throws -> AITaskRouteResult
}

extension AITaskRoutingServicing {
    func route(
        _ taskType: AITaskType,
        for evidenceItem: EvidenceItem,
        in modelContext: ModelContext,
        userTriggered: Bool
    ) async throws -> AITaskRouteResult {
        try await route(
            taskType,
            for: evidenceItem,
            in: modelContext,
            userTriggered: userTriggered,
            idempotencyKey: nil
        )
    }

    func route(
        _ taskType: AITaskType,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool
    ) async throws -> AITaskRouteResult {
        try await route(
            taskType,
            for: caseFile,
            in: modelContext,
            userTriggered: userTriggered,
            idempotencyKey: nil
        )
    }

    func routeStreaming(
        _ taskType: AITaskType,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> AITaskRouteResult {
        try await routeStreaming(
            taskType,
            for: caseFile,
            in: modelContext,
            userTriggered: userTriggered,
            idempotencyKey: nil,
            onDelta: onDelta
        )
    }

    func cleanUpNote(
        for evidenceItem: EvidenceItem,
        userNote: String,
        in modelContext: ModelContext,
        userTriggered: Bool
    ) async throws -> AITaskRouteResult {
        try await cleanUpNote(
            for: evidenceItem,
            userNote: userNote,
            in: modelContext,
            userTriggered: userTriggered,
            idempotencyKey: nil
        )
    }
}

@MainActor
final class AITaskRouter: AITaskRoutingServicing {
    private let aiProxy: any AIProxyServicing
    private let promptVersion: String
    private let textCompressor: AITextCompressor

    init(
        aiProxy: any AIProxyServicing,
        promptVersion: String = "proofkit-ai-routing-v1",
        maxInputCharacters: Int = 8_000
    ) {
        self.aiProxy = aiProxy
        self.promptVersion = promptVersion
        self.textCompressor = AITextCompressor(maxCharacters: maxInputCharacters)
    }

    func route(
        _ taskType: AITaskType,
        for evidenceItem: EvidenceItem,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String? = nil
    ) async throws -> AITaskRouteResult {
        guard !taskType.isCaseLevelTask else {
            throw ProofKitError.remotePolicyViolation("\(taskType.displayName) requires a case, not a single proof item.")
        }

        guard userTriggered else {
            throw ProofKitError.localOnlyViolation("AI tasks must be explicitly triggered by the user.")
        }

        let payload = buildEvidencePayload(taskType: taskType, evidenceItem: evidenceItem, userTriggered: userTriggered)
        return try await execute(payload, modelContext: modelContext, caseFile: evidenceItem.caseFile, evidenceItem: evidenceItem, idempotencyKey: idempotencyKey)
    }

    func route(
        _ taskType: AITaskType,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String? = nil
    ) async throws -> AITaskRouteResult {
        guard taskType.isCaseLevelTask else {
            throw ProofKitError.remotePolicyViolation("\(taskType.displayName) requires a single proof item.")
        }

        guard userTriggered else {
            throw ProofKitError.localOnlyViolation("AI tasks must be explicitly triggered by the user.")
        }

        let payload = buildCasePayload(taskType: taskType, caseFile: caseFile, userTriggered: userTriggered)
        return try await execute(payload, modelContext: modelContext, caseFile: caseFile, evidenceItem: nil, idempotencyKey: idempotencyKey)
    }

    func routeStreaming(
        _ taskType: AITaskType,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String? = nil,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> AITaskRouteResult {
        guard taskType.isCaseLevelTask else {
            throw ProofKitError.remotePolicyViolation("\(taskType.displayName) requires a single proof item.")
        }

        guard userTriggered else {
            throw ProofKitError.localOnlyViolation("AI tasks must be explicitly triggered by the user.")
        }

        let payload = buildCasePayload(taskType: taskType, caseFile: caseFile, userTriggered: userTriggered)
        return try await executeStreaming(
            payload,
            modelContext: modelContext,
            caseFile: caseFile,
            evidenceItem: nil,
            idempotencyKey: idempotencyKey,
            onDelta: onDelta
        )
    }

    func cleanUpNote(
        for evidenceItem: EvidenceItem,
        userNote: String,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String? = nil
    ) async throws -> AITaskRouteResult {
        guard userTriggered else {
            throw ProofKitError.localOnlyViolation("AI cleanup must be explicitly triggered by the user.")
        }

        let trimmedUserNote = userNote.aiRoutingTrimmedText
        guard !trimmedUserNote.isEmpty else {
            throw ProofKitError.remotePolicyViolation("Add a user note before cleaning it up with AI.")
        }

        let payload = buildRewriteNotePayload(
            evidenceItem: evidenceItem,
            userNote: trimmedUserNote,
            userTriggered: userTriggered
        )
        return try await execute(payload, modelContext: modelContext, caseFile: evidenceItem.caseFile, evidenceItem: evidenceItem, idempotencyKey: idempotencyKey)
    }
}

private extension AITaskRouter {
    struct Payload {
        let taskType: AITaskType
        let caseID: UUID?
        let evidenceItemID: UUID?
        let evidenceItemIDs: [UUID]
        let compressedTextInput: String
        let metadata: [String: String]
        let inputHash: String
        let sourceTextHash: String
        let metadataHash: String
        let userTriggered: Bool
    }

    func execute(
        _ payload: Payload,
        modelContext: ModelContext,
        caseFile: CaseFile?,
        evidenceItem: EvidenceItem?,
        idempotencyKey: String?
    ) async throws -> AITaskRouteResult {
        if let cached = try cachedResult(for: payload, in: modelContext) {
            return cached
        }

        let proxyRequest = AIProxyTextRequest(
            taskType: payload.taskType,
            compressedTextInput: payload.compressedTextInput,
            inputHash: payload.inputHash,
            caseID: payload.caseID,
            evidenceItemID: payload.evidenceItemID,
            evidenceItemIDs: payload.evidenceItemIDs,
            metadata: payload.metadata,
            userTriggered: payload.userTriggered,
            idempotencyKey: idempotencyKey ?? payload.inputHash
        )

        let response = try await aiProxy.invokeTextOnlyAI(proxyRequest)
        let cache = try store(response: response, for: payload, in: modelContext, caseFile: caseFile, evidenceItem: evidenceItem)

        return AITaskRouteResult(
            taskType: payload.taskType,
            caseID: payload.caseID,
            evidenceItemID: payload.evidenceItemID,
            inputHash: payload.inputHash,
            compressedTextInput: payload.compressedTextInput,
            outputText: response.outputText,
            responseMetadata: response.metadata ?? [:],
            creditsUsed: response.creditsUsed,
            remainingCredits: response.remainingCredits,
            cacheID: cache.id,
            wasCacheHit: false
        )
    }

    func executeStreaming(
        _ payload: Payload,
        modelContext: ModelContext,
        caseFile: CaseFile?,
        evidenceItem: EvidenceItem?,
        idempotencyKey: String?,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> AITaskRouteResult {
        if let cached = try cachedResult(for: payload, in: modelContext) {
            onDelta(cached.outputText)
            return cached
        }

        let proxyRequest = AIProxyTextRequest(
            taskType: payload.taskType,
            compressedTextInput: payload.compressedTextInput,
            inputHash: payload.inputHash,
            caseID: payload.caseID,
            evidenceItemID: payload.evidenceItemID,
            evidenceItemIDs: payload.evidenceItemIDs,
            metadata: payload.metadata,
            userTriggered: payload.userTriggered,
            idempotencyKey: idempotencyKey ?? payload.inputHash,
            stream: true
        )

        var finalResponse: AIProxyTextResponse?
        for try await event in aiProxy.streamTextOnlyAI(proxyRequest) {
            switch event {
            case .started:
                continue
            case .textDelta(let text):
                onDelta(text)
            case .completed(let response):
                finalResponse = response
            }
        }

        guard let response = finalResponse else {
            throw ProofKitError.remotePolicyViolation("AI proxy stream ended before returning a result.")
        }

        let cache = try store(response: response, for: payload, in: modelContext, caseFile: caseFile, evidenceItem: evidenceItem)
        return AITaskRouteResult(
            taskType: payload.taskType,
            caseID: payload.caseID,
            evidenceItemID: payload.evidenceItemID,
            inputHash: payload.inputHash,
            compressedTextInput: payload.compressedTextInput,
            outputText: response.outputText,
            responseMetadata: response.metadata ?? [:],
            creditsUsed: response.creditsUsed,
            remainingCredits: response.remainingCredits,
            cacheID: cache.id,
            wasCacheHit: false
        )
    }

    func cachedResult(for payload: Payload, in modelContext: ModelContext) throws -> AITaskRouteResult? {
        let taskRawValue = payload.taskType.rawValue
        let inputHash = payload.inputHash
        let descriptor = FetchDescriptor<AIResultCache>(
            predicate: #Predicate<AIResultCache> { cache in
                cache.taskTypeRawValue == taskRawValue && cache.inputFingerprint == inputHash
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let cache = try modelContext.fetch(descriptor).first(where: { !$0.isExpired }),
              let data = cache.resultJSON.data(using: .utf8),
              let response = try? JSONDecoder().decode(AIProxyTextResponse.self, from: data) else {
            return nil
        }

        return AITaskRouteResult(
            taskType: payload.taskType,
            caseID: payload.caseID,
            evidenceItemID: payload.evidenceItemID,
            inputHash: payload.inputHash,
            compressedTextInput: payload.compressedTextInput,
            outputText: response.outputText,
            responseMetadata: response.metadata ?? [:],
            creditsUsed: response.creditsUsed,
            remainingCredits: response.remainingCredits,
            cacheID: cache.id,
            wasCacheHit: true
        )
    }

    func store(
        response: AIProxyTextResponse,
        for payload: Payload,
        in modelContext: ModelContext,
        caseFile: CaseFile?,
        evidenceItem: EvidenceItem?
    ) throws -> AIResultCache {
        let resultJSON = try String(data: JSONEncoder().encode(response), encoding: .utf8) ?? "{}"
        let cache = AIResultCache(
            taskType: payload.taskType,
            inputFingerprint: payload.inputHash,
            sourceTextFingerprint: payload.sourceTextHash,
            metadataFingerprint: payload.metadataHash,
            resultJSON: resultJSON,
            modelIdentifier: response.metadata?["model"],
            promptVersion: promptVersion,
            userTriggered: payload.userTriggered,
            caseFile: caseFile,
            evidenceItem: evidenceItem
        )

        modelContext.insert(cache)
        try modelContext.save()
        return cache
    }

    func buildEvidencePayload(taskType: AITaskType, evidenceItem: EvidenceItem, userTriggered: Bool) -> Payload {
        let metadata = sanitizedEvidenceMetadata(for: evidenceItem, taskType: taskType)
        let compressedTextInput = textCompressor.compress(sections: evidenceSections(for: evidenceItem, taskType: taskType))
        return payload(
            taskType: taskType,
            caseID: evidenceItem.caseFile?.id,
            evidenceItemID: evidenceItem.id,
            evidenceItemIDs: [evidenceItem.id],
            compressedTextInput: compressedTextInput,
            metadata: metadata,
            userTriggered: userTriggered
        )
    }

    func buildRewriteNotePayload(evidenceItem: EvidenceItem, userNote: String, userTriggered: Bool) -> Payload {
        let taskType = AITaskType.rewriteNote
        let metadata = sanitizedEvidenceMetadata(for: evidenceItem, taskType: taskType)
        let compressedTextInput = textCompressor.compress(
            sections: rewriteNoteSections(for: evidenceItem, userNote: userNote)
        )
        return payload(
            taskType: taskType,
            caseID: evidenceItem.caseFile?.id,
            evidenceItemID: evidenceItem.id,
            evidenceItemIDs: [evidenceItem.id],
            compressedTextInput: compressedTextInput,
            metadata: metadata,
            userTriggered: userTriggered
        )
    }

    func buildCasePayload(taskType: AITaskType, caseFile: CaseFile, userTriggered: Bool) -> Payload {
        let metadata = sanitizedCaseMetadata(for: caseFile, taskType: taskType)
        let compressedTextInput = textCompressor.compress(sections: caseSections(for: caseFile, taskType: taskType))
        return payload(
            taskType: taskType,
            caseID: caseFile.id,
            evidenceItemID: nil,
            evidenceItemIDs: caseFile.sortedEvidenceItems.map(\.id),
            compressedTextInput: compressedTextInput,
            metadata: metadata,
            userTriggered: userTriggered
        )
    }

    func payload(
        taskType: AITaskType,
        caseID: UUID?,
        evidenceItemID: UUID?,
        evidenceItemIDs: [UUID],
        compressedTextInput: String,
        metadata: [String: String],
        userTriggered: Bool
    ) -> Payload {
        let sourceTextHash = AIInputHasher.sha256Hex(compressedTextInput)
        let metadataHash = AIInputHasher.sha256Hex(AIInputHasher.canonicalMetadataString(metadata))
        let inputHash = AIInputHasher.hashRequest(
            taskType: taskType,
            promptVersion: promptVersion,
            caseID: caseID,
            evidenceItemID: evidenceItemID,
            evidenceItemIDs: evidenceItemIDs,
            compressedTextInput: compressedTextInput,
            metadata: metadata
        )

        return Payload(
            taskType: taskType,
            caseID: caseID,
            evidenceItemID: evidenceItemID,
            evidenceItemIDs: evidenceItemIDs,
            compressedTextInput: compressedTextInput,
            metadata: metadata,
            inputHash: inputHash,
            sourceTextHash: sourceTextHash,
            metadataHash: metadataHash,
            userTriggered: userTriggered
        )
    }
}

private extension AITaskRouter {
    func evidenceSections(for item: EvidenceItem, taskType: AITaskType) -> [AITextSection] {
        if taskType == .rewriteNote {
            return rewriteNoteSections(for: item, userNote: item.userNotes)
        }

        var sections: [AITextSection] = [
            .metadata("Task", taskDirective(for: taskType)),
            .metadata("Evidence metadata", evidenceMetadataText(for: item)),
            .user("User title", item.userTitle),
            .user("User note", item.userNotes),
            .user("User cleaned note", item.userCleanedNote),
            .user("Why this matters", item.userWhyThisMatters),
            .ocr("Local OCR excerpt", item.originalOCRText)
        ]

        let attachmentOCR = item.sortedAttachments
            .map(\.originalOCRText)
            .joined(separator: "\n\n")
        sections.append(.ocr("Attachment OCR excerpts", attachmentOCR))

        if taskType == .classifyEvidence {
            let categories = EvidenceCategory.allCases.map(\.rawValue).joined(separator: ", ")
            sections.append(.metadata("Allowed evidence categories", categories))
        }

        return sections
    }

    func rewriteNoteSections(for item: EvidenceItem, userNote: String) -> [AITextSection] {
        [
            .metadata("Evidence metadata", evidenceMetadataText(for: item)),
            .user("User note", userNote),
            AITextSection(
                title: "Relevant local OCR excerpt",
                text: relevantOCRExcerpt(for: item, userNote: userNote),
                maxCharacters: 1_800
            )
        ]
    }

    func caseSections(for caseFile: CaseFile, taskType: AITaskType) -> [AITextSection] {
        if taskType == .summarizeTimeline {
            return timelineSummarySections(for: caseFile, taskType: taskType)
        }

        return [
            .metadata("Task", taskDirective(for: taskType)),
            .metadata("Case metadata", caseMetadataText(for: caseFile)),
            .user("User case title", caseFile.userTitle),
            .user("User case summary", caseFile.userSummary),
            .user("User case notes", caseFile.userNotes),
            .ocr("Evidence timeline excerpts", evidenceTimelineText(for: caseFile))
        ]
    }

    func timelineSummarySections(for caseFile: CaseFile, taskType: AITaskType) -> [AITextSection] {
        let selectedItems = selectedTimelineEvidenceItems(for: caseFile)
        return [
            AITextSection(title: "Task", text: taskDirective(for: taskType), maxCharacters: 240),
            AITextSection(title: "Case snapshot", text: caseMetadataText(for: caseFile), maxCharacters: 420),
            AITextSection(title: "Evidence selection note", text: timelineSelectionNote(totalCount: caseFile.evidenceItems.count, selectedCount: selectedItems.count), maxCharacters: 360),
            AITextSection(title: "User case title", text: caseFile.userTitle, maxCharacters: 180),
            AITextSection(title: "Short case context", text: conciseCaseContext(for: caseFile), maxCharacters: 700),
            AITextSection(title: "Selected timeline excerpts", text: timelineSummaryEvidenceText(for: selectedItems), maxCharacters: 5_800)
        ]
    }

    func taskDirective(for taskType: AITaskType) -> String {
        switch taskType {
        case .rewriteNote:
            "Clean up the user's note for clarity while preserving its meaning."
        case .suggestTitle:
            "Suggest a short factual evidence title."
        case .classifyEvidence:
            "Choose the best evidence category from the allowed categories."
        case .summarizeItem:
            "Summarize this proof item in concise neutral language."
        case .summarizeTimeline:
            "Create a concise chronological timeline summary from selected local excerpts."
        case .finalCaseNarrative:
            "Polish the documented records into a neutral proof-packet narrative."
        }
    }

    func evidenceMetadataText(for item: EvidenceItem) -> String {
        [
            "caseType: \(item.caseFile?.caseType.rawValue ?? "none")",
            "category: \(item.category.rawValue)",
            "eventDate: \(formattedDate(item.eventDate))",
            "eventDateSource: \(item.eventDateSource.rawValue)",
            "important: \(item.userMarkedImportant)",
            "reviewed: \(item.isReviewed)",
            "attachmentCount: \(item.attachments.count)"
        ].joined(separator: "\n")
    }

    func caseMetadataText(for caseFile: CaseFile) -> String {
        [
            "caseType: \(caseFile.caseType.rawValue)",
            "status: \(caseFile.status.rawValue)",
            "evidenceCount: \(caseFile.evidenceItems.count)",
            "createdAt: \(formattedDate(caseFile.createdAt))",
            "updatedAt: \(formattedDate(caseFile.updatedAt))"
        ].joined(separator: "\n")
    }

    func conciseCaseContext(for caseFile: CaseFile) -> String {
        [
            ("summary excerpt", caseFile.userSummary.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 320)),
            ("note excerpt", caseFile.userNotes.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 320))
        ]
        .filter { !$0.1.isEmpty }
        .map { "\($0.0): \($0.1)" }
        .joined(separator: "\n")
    }

    func selectedTimelineEvidenceItems(for caseFile: CaseFile, limit: Int = 12) -> [EvidenceItem] {
        let sortedItems = caseFile.sortedEvidenceItems
        guard sortedItems.count > limit else { return sortedItems }

        var selectedIDs = Set<UUID>()
        var selectedItems: [EvidenceItem] = []

        func add(_ items: [EvidenceItem]) {
            for item in items where selectedItems.count < limit {
                guard !selectedIDs.contains(item.id) else { continue }
                selectedIDs.insert(item.id)
                selectedItems.append(item)
            }
        }

        add(sortedItems.filter(\.userMarkedImportant))
        add(sortedItems.filter { $0.eventDate != nil })
        add(sortedItems.sorted { lhs, rhs in
            let lhsDate = lhs.eventDate ?? lhs.updatedAt
            let rhsDate = rhs.eventDate ?? rhs.updatedAt
            return lhsDate > rhsDate
        })

        return selectedItems.sorted { lhs, rhs in
            let lhsDate = lhs.eventDate ?? lhs.createdAt
            let rhsDate = rhs.eventDate ?? rhs.createdAt
            return lhsDate < rhsDate
        }
    }

    func timelineSelectionNote(totalCount: Int, selectedCount: Int) -> String {
        guard totalCount > selectedCount else {
            return "All \(totalCount) proof item\(totalCount == 1 ? "" : "s") are included. Local excerpts are capped per item."
        }

        return "Selected \(selectedCount) of \(totalCount) proof items. Selection prioritized user-marked important items, dated items, and recent items. Only selected excerpts are included."
    }

    func timelineSummaryEvidenceText(for items: [EvidenceItem]) -> String {
        items.map { item in
            let note = item.userCleanedNote.aiRoutingTrimmedText.isEmpty ? item.userNotes : item.userCleanedNote
            return """
            Proof item
            date: \(formattedDate(item.eventDate))
            category: \(item.category.rawValue)
            important: \(item.userMarkedImportant)
            title excerpt: \(item.userTitle.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 120))
            note excerpt: \(note.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 260))
            why this matters excerpt: \(item.userWhyThisMatters.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 180))
            OCR excerpt: \(timelineOCRExcerpt(for: item))
            """
        }
        .joined(separator: "\n\n---\n\n")
    }

    func timelineOCRExcerpt(for item: EvidenceItem) -> String {
        ([item.originalOCRText] + item.sortedAttachments.map(\.originalOCRText))
            .map(\.aiRoutingCollapsedWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .truncatedForAIRouting(to: 320)
    }

    func evidenceTimelineText(for caseFile: CaseFile) -> String {
        caseFile.sortedEvidenceItems.map { item in
            let note = item.userCleanedNote.aiRoutingTrimmedText.isEmpty ? item.userNotes : item.userCleanedNote
            return """
            Proof item
            date: \(formattedDate(item.eventDate))
            category: \(item.category.rawValue)
            important: \(item.userMarkedImportant)
            title excerpt: \(item.userTitle.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 180))
            note excerpt: \(note.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 500))
            why this matters: \(item.userWhyThisMatters.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 350))
            OCR excerpt: \(item.originalOCRText.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 650))
            """
        }
        .joined(separator: "\n\n---\n\n")
    }

    func relevantOCRExcerpt(for item: EvidenceItem, userNote: String) -> String {
        let combinedOCR = ([item.originalOCRText] + item.sortedAttachments.map(\.originalOCRText))
            .map(\.aiRoutingTrimmedText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !combinedOCR.isEmpty else { return "" }

        let keywords = rewriteKeywordSet(from: userNote)
        guard !keywords.isEmpty else {
            return combinedOCR.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 1_800)
        }

        let lines = combinedOCR
            .components(separatedBy: .newlines)
            .map(\.aiRoutingCollapsedWhitespace)
            .filter { !$0.isEmpty }

        let matchedLines = lines.filter { line in
            let normalizedLine = line.lowercased()
            return keywords.contains { normalizedLine.contains($0) }
        }

        let relevantText = matchedLines.isEmpty ? combinedOCR : matchedLines.joined(separator: "\n")
        return relevantText.aiRoutingCollapsedWhitespace.truncatedForAIRouting(to: 1_800)
    }

    func rewriteKeywordSet(from userNote: String) -> [String] {
        let stopwords: Set<String> = [
            "about", "after", "again", "also", "because", "before", "could",
            "from", "have", "into", "just", "like", "note", "only", "over",
            "that", "their", "them", "then", "there", "this", "under", "very",
            "were", "what", "when", "where", "with", "would"
        ]

        let tokens = userNote
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.aiRoutingTrimmedText }
            .filter { token in
                token.count >= 4 && !stopwords.contains(token)
            }

        return Array(Set(tokens)).sorted()
    }
}

private extension AITaskRouter {
    func sanitizedEvidenceMetadata(for item: EvidenceItem, taskType: AITaskType) -> [String: String] {
        sanitizeMetadata([
            "task": taskType.rawValue,
            "source": "evidenceItem",
            "caseType": item.caseFile?.caseType.rawValue ?? "",
            "category": item.category.rawValue,
            "eventDate": formattedDate(item.eventDate),
            "eventDateSource": item.eventDateSource.rawValue,
            "important": String(item.userMarkedImportant),
            "reviewed": String(item.isReviewed),
            "attachmentCount": String(item.attachments.count)
        ])
    }

    func sanitizedCaseMetadata(for caseFile: CaseFile, taskType: AITaskType) -> [String: String] {
        sanitizeMetadata([
            "task": taskType.rawValue,
            "source": "caseFile",
            "caseType": caseFile.caseType.rawValue,
            "status": caseFile.status.rawValue,
            "evidenceCount": String(caseFile.evidenceItems.count),
            "importantEvidenceCount": String(caseFile.evidenceItems.filter(\.userMarkedImportant).count)
        ])
    }

    func sanitizeMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { partialResult, pair in
            let key = pair.key.aiRoutingMetadataSafeKey
            let value = pair.value.aiRoutingMetadataSafeValue
            guard !key.isEmpty, !value.isEmpty else { return }
            partialResult[key] = value
        }
    }

    func formattedDate(_ date: Date?) -> String {
        guard let date else { return "none" }
        return Self.iso8601.string(from: date)
    }

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct AITextSection {
    let title: String
    let text: String
    let maxCharacters: Int

    static func metadata(_ title: String, _ text: String) -> AITextSection {
        AITextSection(title: title, text: text, maxCharacters: 1_200)
    }

    static func user(_ title: String, _ text: String) -> AITextSection {
        AITextSection(title: title, text: text, maxCharacters: 2_000)
    }

    static func ocr(_ title: String, _ text: String) -> AITextSection {
        AITextSection(title: title, text: text, maxCharacters: 2_400)
    }
}

private struct AITextCompressor {
    let maxCharacters: Int

    func compress(sections: [AITextSection]) -> String {
        var remainingCharacters = maxCharacters
        var compressedSections: [String] = []

        for section in sections {
            guard remainingCharacters > 0 else { break }

            let cleanedText = section.text.aiRoutingCollapsedWhitespace
            guard !cleanedText.isEmpty else { continue }

            let header = "## \(section.title)\n"
            let allowance = max(0, min(section.maxCharacters, remainingCharacters - header.count - 2))
            guard allowance > 0 else { break }

            let excerpt = cleanedText.truncatedForAIRouting(to: allowance)
            let rendered = header + excerpt
            compressedSections.append(rendered)
            remainingCharacters -= rendered.count + 2
        }

        return compressedSections.joined(separator: "\n\n")
    }
}

private enum AIInputHasher {
    static func hashRequest(
        taskType: AITaskType,
        promptVersion: String,
        caseID: UUID?,
        evidenceItemID: UUID?,
        evidenceItemIDs: [UUID],
        compressedTextInput: String,
        metadata: [String: String]
    ) -> String {
        let canonical = [
            "task=\(taskType.rawValue)",
            "promptVersion=\(promptVersion)",
            "caseID=\(caseID?.uuidString ?? "")",
            "evidenceItemID=\(evidenceItemID?.uuidString ?? "")",
            "evidenceItemIDs=\(evidenceItemIDs.map(\.uuidString).sorted().joined(separator: ","))",
            "metadata=\(canonicalMetadataString(metadata))",
            "input=\(compressedTextInput)"
        ].joined(separator: "\n")

        return sha256Hex(canonical)
    }

    static func canonicalMetadataString(_ metadata: [String: String]) -> String {
        metadata.keys.sorted().map { key in
            "\(key)=\(metadata[key] ?? "")"
        }
        .joined(separator: "\n")
    }

    static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var aiRoutingTrimmedText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var aiRoutingCollapsedWhitespace: String {
        aiRoutingTrimmedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var lastPathComponentOnly: String {
        (self as NSString).lastPathComponent.aiRoutingCollapsedWhitespace
    }

    var aiRoutingMetadataSafeKey: String {
        aiRoutingCollapsedWhitespace
            .replacingOccurrences(of: " ", with: "_")
            .filter { character in
                character.isLetter || character.isNumber || character == "_" || character == "-"
            }
    }

    var aiRoutingMetadataSafeValue: String {
        aiRoutingCollapsedWhitespace
            .replacingOccurrences(of: "file://", with: "")
            .truncatedForAIRouting(to: 500)
    }

    func truncatedForAIRouting(to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard count > limit else { return self }

        if limit <= 16 {
            return String(prefix(limit))
        }

        let marker = " … "
        let available = max(0, limit - marker.count)
        let headCount = Int(Double(available) * 0.65)
        let tailCount = available - headCount
        return String(prefix(headCount)) + marker + String(suffix(tailCount))
    }
}
