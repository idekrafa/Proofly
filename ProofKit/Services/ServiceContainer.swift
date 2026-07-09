import SwiftUI

struct ServiceContainer {
    let localStorage: any LocalStorageServicing
    let ocr: any OCRServicing
    let dateCandidateExtractor: any DateCandidateExtracting
    let pdfExporter: any PDFExportServicing
    let account: any AccountServicing
    let purchaseEntitlements: any PurchaseEntitlementServicing
    let signatureValidation: any PDFSignatureValidationServicing
    let signatureRequests: any SignatureRequestServicing
    let subscriptions: any SubscriptionServicing
    let paywall: any PaywallServicing
    let serviceHealth: ServiceHealthMonitor
    let evidenceCase: any EvidenceCaseServicing
    let analytics: any AnalyticsTracking

    private static let supabaseInfrastructure = SupabaseInfrastructureService.live()
    private static let subscriptionService = RevenueCatSubscriptionService.live()
    private static let paywallService = PlaceholderPaywallService(
        purchaseEntitlements: supabaseInfrastructure,
        subscriptions: subscriptionService
    )
    private static let serviceHealthMonitor = ServiceHealthMonitor(
        purchaseEntitlements: supabaseInfrastructure,
        account: supabaseInfrastructure
    )

    static let live = ServiceContainer(
        localStorage: LocalStorageService(),
        ocr: OCRService(),
        dateCandidateExtractor: DateCandidateExtractionService(),
        pdfExporter: PDFExportService(),
        account: supabaseInfrastructure,
        purchaseEntitlements: supabaseInfrastructure,
        signatureValidation: supabaseInfrastructure,
        signatureRequests: supabaseInfrastructure,
        subscriptions: subscriptionService,
        paywall: paywallService,
        serviceHealth: serviceHealthMonitor,
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
            purchaseEntitlements: purchaseEntitlements,
            signatureValidation: signatureValidation,
            signatureRequests: signatureRequests,
            subscriptions: subscriptions,
            paywall: paywall,
            serviceHealth: serviceHealth,
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
