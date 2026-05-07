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
    let paywall: any PaywallServicing
    let aiRouter: any AITaskRoutingServicing
    let ai: any AITextAnalysisServicing
    let evidenceCase: any EvidenceCaseServicing

    private static let supabaseInfrastructure = SupabaseInfrastructureService.live()
    private static let paywallService = PlaceholderPaywallService(purchaseEntitlements: supabaseInfrastructure)
    private static let aiTaskRouter = AITaskRouter(aiProxy: supabaseInfrastructure)

    static let live = ServiceContainer(
        localStorage: LocalStorageService(),
        ocr: OCRService(),
        dateCandidateExtractor: DateCandidateExtractionService(),
        pdfExporter: PDFExportService(),
        account: supabaseInfrastructure,
        aiCredits: supabaseInfrastructure,
        aiProxy: supabaseInfrastructure,
        purchaseEntitlements: supabaseInfrastructure,
        paywall: paywallService,
        aiRouter: aiTaskRouter,
        ai: TextOnlyAIPlaceholderService(),
        evidenceCase: EvidenceCaseService()
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
            paywall: paywall,
            aiRouter: aiRouter,
            ai: ai,
            evidenceCase: evidenceCase
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
