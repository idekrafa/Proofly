import Foundation
import SwiftData

@MainActor
protocol AIActionServicing {
    func quoteAction(_ actionKind: AIActionKind, caseID: UUID) async throws -> AIUsageQuote
    func runAIAction(
        feature: String,
        caseId: UUID,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> AITaskRouteResult
    func runAction(
        _ actionKind: AIActionKind,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool
    ) async throws -> AITaskRouteResult
    func runQueuedAction(
        _ actionKind: AIActionKind,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String
    ) async throws -> AITaskRouteResult
}

@MainActor
final class AIService: AIActionServicing {
    private let aiCredits: any AICreditTrackingServicing
    private let paywall: any PaywallServicing
    private let aiRouter: any AITaskRoutingServicing

    init(
        aiCredits: any AICreditTrackingServicing,
        paywall: any PaywallServicing,
        aiRouter: any AITaskRoutingServicing
    ) {
        self.aiCredits = aiCredits
        self.paywall = paywall
        self.aiRouter = aiRouter
    }

    func quoteAction(_ actionKind: AIActionKind, caseID: UUID) async throws -> AIUsageQuote {
        _ = caseID

        let accessDecision = await paywall.canUseAI()
        guard accessDecision.isAllowed else {
            throw ProofKitError.planLimitReached(accessDecision.message)
        }

        let balance = try await aiCredits.fetchAICreditBalance()
        let creditCost = actionKind.defaultCreditCost
        guard balance.availableCredits >= creditCost else {
            let creditPhrase = String(localized: "\(creditCost) AI credit")
            throw ProofKitError.planLimitReached(
                String(localized: "\(actionKind.displayName) uses \(creditPhrase), but you have \(balance.availableCredits) available. Local OCR and timeline editing are still free.")
            )
        }

        return AIUsageQuote(
            feature: actionKind,
            creditCost: creditCost,
            creditsRemainingBefore: balance.availableCredits,
            creditsRemainingAfter: max(0, balance.availableCredits - creditCost),
            estimatedWaitMessage: actionKind.estimatedWaitMessage
        )
    }

    func runAIAction(
        feature: String,
        caseId: UUID,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> AITaskRouteResult {
        guard caseFile.id == caseId else {
            throw ProofKitError.remotePolicyViolation("The selected case does not match the AI request.")
        }

        guard let actionKind = AIActionKind(rawValue: feature) else {
            throw ProofKitError.notImplemented(feature)
        }

        guard actionKind == .timelineSummary || actionKind == .packetPolish else {
            throw ProofKitError.notImplemented(actionKind.displayName)
        }

        _ = try await quoteAction(actionKind, caseID: caseId)

        return try await aiRouter.routeStreaming(
            actionKind.taskType,
            for: caseFile,
            in: modelContext,
            userTriggered: true,
            idempotencyKey: nil,
            onDelta: onDelta
        )
    }

    func runAction(
        _ actionKind: AIActionKind,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool
    ) async throws -> AITaskRouteResult {
        guard actionKind == .timelineSummary || actionKind == .packetPolish else {
            throw ProofKitError.notImplemented(actionKind.displayName)
        }

        return try await aiRouter.route(
            actionKind.taskType,
            for: caseFile,
            in: modelContext,
            userTriggered: userTriggered
        )
    }

    func runQueuedAction(
        _ actionKind: AIActionKind,
        for caseFile: CaseFile,
        in modelContext: ModelContext,
        userTriggered: Bool,
        idempotencyKey: String
    ) async throws -> AITaskRouteResult {
        guard actionKind == .timelineSummary || actionKind == .packetPolish else {
            throw ProofKitError.notImplemented(actionKind.displayName)
        }

        return try await aiRouter.route(
            actionKind.taskType,
            for: caseFile,
            in: modelContext,
            userTriggered: userTriggered,
            idempotencyKey: idempotencyKey
        )
    }
}
