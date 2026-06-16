import SwiftUI

struct ServiceContainer {
    let localStorage: any LocalStorageServicing
    let ocr: any OCRServicing
    let dateCandidateExtractor: any DateCandidateExtracting
    let pdfExporter: any PDFExportServicing
    let account: any AccountServicing
    let aiCredits: any AICreditTrackingServicing
    let aiProxy: any AIProxyServicing
    let purchaseEntitlements: any PurchaseEntitlementServicing
    let signatureValidation: any PDFSignatureValidationServicing
    let subscriptions: any SubscriptionServicing
    let paywall: any PaywallServicing
    let aiRouter: any AITaskRoutingServicing
    let aiActions: any AIActionServicing
    let serviceHealth: ServiceHealthMonitor
    let aiQueue: AIRequestQueueService
    let ai: any AITextAnalysisServicing
    let evidenceCase: any EvidenceCaseServicing
    let analytics: any AnalyticsTracking

    private static let supabaseInfrastructure = SupabaseInfrastructureService.live()
    private static let subscriptionService = RevenueCatSubscriptionService.live()
    private static let paywallService = PlaceholderPaywallService(
        purchaseEntitlements: supabaseInfrastructure,
        subscriptions: subscriptionService
    )
    private static let aiTaskRouter = AITaskRouter(aiProxy: supabaseInfrastructure)
    private static let aiActionService = AIService(
        aiCredits: supabaseInfrastructure,
        paywall: paywallService,
        aiRouter: aiTaskRouter
    )
    private static let serviceHealthMonitor = ServiceHealthMonitor(
        aiCredits: supabaseInfrastructure,
        account: supabaseInfrastructure
    )
    private static let aiRequestQueueService = AIRequestQueueService(
        aiCredits: supabaseInfrastructure,
        aiActions: aiActionService,
        aiRouter: aiTaskRouter,
        serviceHealth: serviceHealthMonitor
    )

    static let live = ServiceContainer(
        localStorage: LocalStorageService(),
        ocr: OCRService(),
        dateCandidateExtractor: DateCandidateExtractionService(),
        pdfExporter: PDFExportService(),
        account: supabaseInfrastructure,
        aiCredits: supabaseInfrastructure,
        aiProxy: supabaseInfrastructure,
        purchaseEntitlements: supabaseInfrastructure,
        signatureValidation: supabaseInfrastructure,
        subscriptions: subscriptionService,
        paywall: paywallService,
        aiRouter: aiTaskRouter,
        aiActions: aiActionService,
        serviceHealth: serviceHealthMonitor,
        aiQueue: aiRequestQueueService,
        ai: TextOnlyAIPlaceholderService(),
        evidenceCase: EvidenceCaseService(),
        analytics: AnalyticsService.live()
    )

    func scoped(to session: ProofKitAccountSession) throws -> ServiceContainer {
        ServiceContainer(
            localStorage: LocalStorageService(baseDirectory: try AccountScopedLocalData.localFilesDirectory(for: session)),
            ocr: ocr,
            dateCandidateExtractor: dateCandidateExtractor,
            pdfExporter: pdfExporter,
            account: account,
            aiCredits: aiCredits,
            aiProxy: aiProxy,
            purchaseEntitlements: purchaseEntitlements,
            signatureValidation: signatureValidation,
            subscriptions: subscriptions,
            paywall: paywall,
            aiRouter: aiRouter,
            aiActions: aiActions,
            serviceHealth: serviceHealth,
            aiQueue: aiQueue,
            ai: ai,
            evidenceCase: evidenceCase,
            analytics: analytics.scoped(to: session)
        )
    }
}

private struct ServiceContainerKey: EnvironmentKey {
    static let defaultValue = ServiceContainer.live
}

extension EnvironmentValues {
    var proofKitServices: ServiceContainer {
        get { self[ServiceContainerKey.self] }
        set { self[ServiceContainerKey.self] = newValue }
    }
}
